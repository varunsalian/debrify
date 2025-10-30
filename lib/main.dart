import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/torrent_search_screen.dart';
import 'screens/debrid_downloads_screen.dart';
import 'screens/torbox/torbox_downloads_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/magic_tv_screen.dart';
import 'screens/playlist_screen.dart';
import 'services/android_native_downloader.dart';
import 'services/storage_service.dart';
import 'widgets/initial_setup_flow.dart';

import 'widgets/animated_background.dart';
import 'widgets/premium_nav_bar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/premium_top_nav.dart';
import 'services/main_page_bridge.dart';
import 'models/rd_torrent.dart';
import 'package:window_manager/window_manager.dart';

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
  } catch (_) {
    _updateFocusHighlightStrategy(false);
    // Fallback to all orientations if detection fails
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _hasRealDebridKey = false;
  bool _hasTorboxKey = false;
  bool _initialSetupHandled = false;
  bool _rdIntegrationEnabled = true;
  bool _tbIntegrationEnabled = true;
  bool _isAndroidTv = false;

  final List<Widget> _pages = [
    const TorrentSearchScreen(),
    const PlaylistScreen(),
    const DownloadsScreen(),
    const DebrifyTVScreen(),
    const DebridDownloadsScreen(),
    const TorboxDownloadsScreen(),
    const SettingsScreen(),
  ];

  final List<String> _titles = [
    'Torrent Search',
    'Playlist',
    'Downloads',
    'Debrify TV',
    'Real Debrid',
    'Torbox',
    'Settings',
  ];

  final List<IconData> _icons = [
    Icons.search_rounded,
    Icons.playlist_play_rounded,
    Icons.download_for_offline_rounded,
    Icons.tv_rounded,
    Icons.cloud_download_rounded,
    Icons.flash_on_rounded,
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
    MainPageBridge.openTorboxAction = (torboxTorrent, action) {
      if (!mounted) return;
      if (!_hasTorboxKey) {
        _showMissingApiKeySnack('Torbox');
        return;
      }
      setState(() {
        _pages[5] = TorboxDownloadsScreen(
          initialTorrentForAction: torboxTorrent,
          initialAction: action,
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

    // Trigger onboarding experience after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleInitialExperience();
    });

    AndroidNativeDownloader.isTelevision().then((isTv) {
      if (!mounted) return;
      setState(() {
        _isAndroidTv = isTv;
        if (_isAndroidTv) {
          _selectedIndex = 3; // Debrify TV
        }
      });
    });
  }

  @override
  void dispose() {
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    MainPageBridge.switchTab = null;
    MainPageBridge.openDebridOptions = null;
    MainPageBridge.openTorboxAction = null;
    _animationController.dispose();
    super.dispose();
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

  Future<void> _handleInitialExperience() async {
    if (_initialSetupHandled) return;
    _initialSetupHandled = true;

    final hasCompleted = await StorageService.isInitialSetupComplete();
    if (hasCompleted || !mounted) return;

    final configured = await InitialSetupFlow.show(context);
    if (!mounted) return;

    await StorageService.setInitialSetupComplete(true);

    if (configured) {
      MainPageBridge.notifyIntegrationChanged();
    }

    _loadIntegrationState();
  }

  void _handleIntegrationChanged() {
    _loadIntegrationState();
  }

  Future<void> _loadIntegrationState() async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = await StorageService.getRealDebridIntegrationEnabled();
    final torboxEnabled = await StorageService.getTorboxIntegrationEnabled();

    if (!mounted) return;

    final hasRealDebrid = rdEnabled && rdKey != null && rdKey.isNotEmpty;
    final hasTorbox = torboxEnabled && torboxKey != null && torboxKey.isNotEmpty;

    _applyIntegrationState(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
      realDebridEnabled: rdEnabled,
      torboxEnabled: torboxEnabled,
    );
  }

  void _applyIntegrationState({
    required bool hasRealDebrid,
    required bool hasTorbox,
    required bool realDebridEnabled,
    required bool torboxEnabled,
  }) {
    final newVisible = _computeVisibleNavIndices(
      hasRealDebrid: hasRealDebrid,
      hasTorbox: hasTorbox,
    );

    int nextIndex = _selectedIndex;
    if (!newVisible.contains(nextIndex)) {
      nextIndex = newVisible.first;
    }

    if (_hasRealDebridKey == hasRealDebrid &&
        _hasTorboxKey == hasTorbox &&
        _rdIntegrationEnabled == realDebridEnabled &&
        _tbIntegrationEnabled == torboxEnabled &&
        nextIndex == _selectedIndex) {
      return;
    }

    setState(() {
      _hasRealDebridKey = hasRealDebrid;
      _hasTorboxKey = hasTorbox;
      _rdIntegrationEnabled = realDebridEnabled;
      _tbIntegrationEnabled = torboxEnabled;
      _selectedIndex = nextIndex;
    });
  }

  List<int> _computeVisibleNavIndices({
    bool? hasRealDebrid,
    bool? hasTorbox,
  }) {
    if (_isAndroidTv) {
      return const [3, 6];
    }

    final rd = hasRealDebrid ?? _hasRealDebridKey;
    final tb = hasTorbox ?? _hasTorboxKey;
    if (!rd && !tb) {
      return const [0, 6];
    }

    final indices = <int>[0, 1, 2, 3];
    if (rd) indices.add(4);
    if (tb) indices.add(5);
    indices.add(6);
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

    return AnimatedPremiumBackground(
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
        body: FadeTransition(
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
    );
  }
}
