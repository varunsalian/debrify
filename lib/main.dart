import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/torrent_search_screen.dart';
import 'screens/debrid_downloads_screen.dart';
import 'screens/torbox/torbox_downloads_screen.dart';
import 'screens/pikpak/pikpak_files_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/magic_tv_screen.dart';
import 'screens/playlist_screen.dart';
import 'services/android_native_downloader.dart';
import 'services/storage_service.dart';
import 'services/debrify_tv_repository.dart';
import 'models/debrify_tv_channel_record.dart';
import 'widgets/app_initializer.dart';
import 'package:collection/collection.dart';

import 'widgets/animated_background.dart';
import 'widgets/premium_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/premium_top_nav.dart';
import 'services/main_page_bridge.dart';
import 'models/rd_torrent.dart';
import 'package:window_manager/window_manager.dart';
import 'services/deep_link_service.dart';
import 'services/magnet_link_handler.dart';
import 'widgets/auto_launch_overlay.dart';

final WindowListener _windowsFullscreenListener = _WindowsFullscreenListener();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    windowManager.addListener(_windowsFullscreenListener);
  }

  // Set a sensible default orientation: phones stay portrait, Android TV uses landscape.
  await _initOrientation();
  // Clean up old playback state data
  await _cleanupPlaybackState();
  runApp(const DebrifyApp());

  if (!kIsWeb && Platform.isWindows) {
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
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

class _WindowsFullscreenListener with WindowListener {
  @override
  Future<void> onWindowEvent(String eventName) async {
    if (!Platform.isWindows) return;
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

class DebrifyApp extends StatelessWidget {
  const DebrifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
              debugPrint('Debrify: TV mode detected: $isTv, text scale: ${isTv ? 1.0 : 1.3}');
            }

            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                // TV: No text scaling (1.0) to prevent zoom issues
                // Mobile: Respect accessibility but cap at 1.3 for layout consistency
                textScaler: TextScaler.linear(
                  isTv ? 1.0 : min(MediaQuery.textScalerOf(context).scale(1.0), 1.3),
                ),
              ),
              child: child!,
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
          primary: Color(0xFF6366F1), // Indigo
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF3730A3),
          onPrimaryContainer: Colors.white,
          secondary: Color(0xFF10B981), // Emerald
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFF065F46),
          onSecondaryContainer: Colors.white,
          tertiary: Color(0xFFF59E0B), // Amber
          onTertiary: Colors.white,
          tertiaryContainer: Color(0xFF92400E),
          onTertiaryContainer: Colors.white,
          surface: Color(0xFF0F172A), // Slate 900
          onSurface: Colors.white,
          surfaceContainerHighest: Color(0xFF1E293B), // Slate 800
          surfaceContainerHigh: Color(0xFF334155), // Slate 700
          surfaceContainer: Color(0xFF475569), // Slate 600
          surfaceContainerLow: Color(0xFF64748B), // Slate 500
          surfaceContainerLowest: Color(0xFF94A3B8), // Slate 400
          background: Color(0xFF020617), // Slate 950
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
          color: const Color(0xFF1E293B),
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
            side: const BorderSide(color: Color(0xFF475569)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF334155),
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
            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
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
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF1E293B)),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
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
  static bool get isAutoLaunchShowingOverlay => _MainPageState.isAutoLaunchShowingOverlay;

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  static String? _startupChannelIdToLaunch;
  static bool _startupChannelIdConsumed = false;

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

  final List<Widget> _pages = [
    const TorrentSearchScreen(),
    const PlaylistScreen(),
    const DownloadsScreen(),
    const DebrifyTVScreen(),
    const DebridDownloadsScreen(),
    const TorboxDownloadsScreen(),
    const PikPakFilesScreen(),
    const SettingsScreen(),
  ];

  final List<String> _titles = [
    'Torrent Search',
    'Playlist',
    'Downloads',
    'Debrify TV',
    'Real Debrid',
    'Torbox',
    'PikPak',
    'Settings',
  ];

  final List<IconData> _icons = [
    Icons.search_rounded,
    Icons.playlist_play_rounded,
    Icons.download_for_offline_rounded,
    Icons.tv_rounded,
    Icons.cloud_download_rounded,
    Icons.flash_on_rounded,
    Icons.cloud_circle_rounded,
    Icons.settings_rounded,
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
      setState(() {
        _pages[4] = DebridDownloadsScreen(initialTorrentForOptions: torrent);
      });
      _onItemTapped(4);
      // Reset the page after a delay to prevent recurring dialogs
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _pages[4] = const DebridDownloadsScreen();
          });
        }
      });
    };
    MainPageBridge.openTorboxFolder = (torboxTorrent) {
      if (!mounted) return;
      if (!_hasTorboxKey) {
        _showMissingApiKeySnack('Torbox');
        return;
      }
      setState(() {
        _pages[5] = TorboxDownloadsScreen(
          initialTorrentToOpen: torboxTorrent,
        );
      });
      _onItemTapped(5);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _pages[5] = const TorboxDownloadsScreen();
          });
        }
      });
    };
    MainPageBridge.openPikPakFolder = (fileId, folderName) {
      if (!mounted) return;
      if (!_pikpakEnabled) {
        _showMissingApiKeySnack('PikPak');
        return;
      }
      setState(() {
        _pages[6] = PikPakFilesScreen(
          initialFolderId: fileId,
          initialFolderName: folderName,
        );
      });
      _onItemTapped(6);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _pages[6] = const PikPakFilesScreen();
          });
        }
      });
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

      // Check if auto-launch is enabled to avoid race condition
      final autoLaunchEnabled = await StorageService.getStartupAutoLaunchEnabled();

      setState(() {
        _isAndroidTv = isTv;
        // Only auto-navigate to Debrify TV if auto-launch is NOT enabled
        // (auto-launch will handle navigation after setting up channel ID)
        if (_isAndroidTv && !autoLaunchEnabled) {
          _selectedIndex = 3; // Debrify TV
        }
      });
    });

    // Initialize deep link service for magnet links
    _initializeDeepLinking();

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
    _animationController.dispose();
    DeepLinkService().dispose();
    super.dispose();
  }

  /// Initialize deep linking for magnet links
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
          await MainPageBridge.handleRealDebridResult?.call(result, torrentName, apiKey);
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
      );

      // Handle the magnet link
      await handler.handleMagnetLink(magnetUri);
    };

    // Initialize the service
    deepLinkService.initialize();
  }

  void _onItemTapped(int index) {
    final visible = _computeVisibleNavIndices();
    if (!visible.contains(index)) {
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    _animationController.reset();
    _animationController.forward();
  }


  void _handleIntegrationChanged() {
    _loadIntegrationState();
  }

  /// Static getter for startup channel ID (used by DebrifyTVScreen)
  static String? _getStartupChannelId() {
    // Check if already consumed (prevents double-read by AnimatedSwitcher)
    if (_startupChannelIdConsumed) {
      debugPrint('MainPage: Startup channel ID already consumed, returning null');
      return null;
    }

    // Mark as consumed and return the value
    _startupChannelIdConsumed = true;
    debugPrint('MainPage: Startup channel ID consumed: $_startupChannelIdToLaunch');
    return _startupChannelIdToLaunch;
  }

  /// Check if startup auto-launch is enabled and navigate to Debrify TV or play playlist item
  Future<void> _checkStartupAutoLaunch() async {
    // Prevent duplicate launches
    if (_autoLaunchInProgress) return;
    _autoLaunchInProgress = true;

    try {
      // Check if auto-launch is enabled
      final autoLaunchEnabled = await StorageService.getStartupAutoLaunchEnabled();
      if (!autoLaunchEnabled) {
        _autoLaunchInProgress = false;
        return;
      }

      // Get startup mode
      final startupMode = await StorageService.getStartupMode();

      if (startupMode == 'playlist') {
        await _launchPlaylistItem();
      } else {
        await _launchChannel();
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
    final selectedChannelId = await StorageService.getStartupChannelId() ?? 'random';

    // Determine which channel to launch
    DebrifyTvChannelRecord channelToLaunch;

    if (selectedChannelId == 'random') {
      final random = Random();
      channelToLaunch = channels[random.nextInt(channels.length)];
    } else {
      final foundChannel = channels.firstWhereOrNull((c) => c.channelId == selectedChannelId);
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
    debugPrint('MainPage: Set startup channel ID: ${channelToLaunch.channelId}');

    // Navigate to Debrify TV tab (index 3) - no delay needed, overlay is showing
    if (!mounted) {
      return;
    }

    _onItemTapped(3); // Debrify TV tab
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

    // Navigate to playlist tab
    setState(() {
      _selectedIndex = 1; // Playlist tab (index 1, not 2)
    });

    // Wait for UI to settle and playlist screen to be built
    await Future.delayed(const Duration(milliseconds: 100));

    // Wait a bit more for the screen to fully initialize
    await Future.delayed(const Duration(milliseconds: 800));

    // Use the exact same playback logic as clicking a playlist card
    final playHandler = MainPageBridge.playPlaylistItem;
    if (playHandler != null) {
      await playHandler(playlistItem);
    } else {
      // As a fallback, store the item to be played
      MainPageBridge.notifyPlaylistItemToAutoPlay(playlistItem);
    }
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
    final hasTorbox = torboxEnabled && torboxKey != null && torboxKey.isNotEmpty;

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
      final indices = <int>[0, 1, 3]; // Torrent, Playlist, Debrify TV
      if (rd && !rdHidden) {
        indices.add(4); // Real Debrid downloads
      }
      if (tb && !tbHidden) {
        indices.add(5); // Torbox downloads
      }
      if (pikpak && !ppHidden) {
        indices.add(6); // PikPak
      }
      indices.add(7); // Settings
      return indices;
    }

    final rd = hasRealDebrid ?? _hasRealDebridKey;
    final rdHidden = realDebridHidden ?? _rdHiddenFromNav;
    final tb = hasTorbox ?? _hasTorboxKey;
    final tbHidden = torboxHidden ?? _tbHiddenFromNav;
    final pikpak = pikpakEnabled ?? _pikpakEnabled;
    final ppHidden = pikpakHidden ?? _pikpakHiddenFromNav;
    if (!rd && !tb && !pikpak) {
      return [0, 7];
    }

    final indices = <int>[0, 1, 2, 3];
    if (rd && !rdHidden) indices.add(4);
    if (tb && !tbHidden) indices.add(5);
    if (pikpak && !ppHidden) indices.add(6);
    indices.add(7);
    return indices;
  }

  void _showMissingApiKeySnack(String provider) {
    final bool integrationDisabled = provider == 'Real Debrid'
        ? !_rdIntegrationEnabled
        : !_tbIntegrationEnabled;
    final message = integrationDisabled
        ? 'Enable $provider in Settings to use this feature.'
        : 'Please add your $provider API key in Settings first!';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  void _showIntegrationRequiredSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Connect Real Debrid or Torbox in Settings to unlock more tabs.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleIndices = _computeVisibleNavIndices();
    final navItems = [
      for (final index in visibleIndices) NavItem(_icons[index], _titles[index]),
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
              final backButtonPressedTwice = _lastBackPressTime != null &&
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
          },
          child: AnimatedPremiumBackground(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: PremiumTopNav(
                  currentIndex: currentNavIndex,
                  items: navItems,
                  onTap: (relativeIndex) {
                    final actualIndex = visibleIndices[relativeIndex];
                    _onItemTapped(actualIndex);
                  },
                  badges: navBadges,
                  haptics: true,
                ),
                automaticallyImplyLeading: false,
              ),
              body: SafeArea(
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
                        child: SlideTransition(position: offsetAnimation, child: child),
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
