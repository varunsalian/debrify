import 'package:flutter/material.dart';
import '../../../utils/tv_reveal.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/main_page_bridge.dart';
import '../../../services/profiles/profile_bootstrap.dart';
import '../../../services/storage_service.dart';
import '../../../theme/app_focus.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_surface.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../theme/widgets/parallax_focus.dart';
import '../../../widgets/shimmer.dart';

/// Shared visual tokens for the Settings screens.
///
/// These mirror the Stremio board constants in `search_screen.dart`
/// (`kStremioBg` / `kStremioAccent`) and `see_all_theme.dart` so Settings
/// finally matches the Discover look. Duplicated on purpose — importing
/// `search_screen.dart` from here would be a layering smell.
const Color kSettingsBg = Color(0xFF0D0B1A);
const Color kSettingsAccent = Color(0xFF7B5CFF);
const Color kSettingsAccent2 = Color(0xFF9B7BFF);
const Color kSettingsPanel = Color(0xFF17132E);
const Color kSettingsPanel2 = Color(0xFF1E1840);
const Color kSettingsGreen = Color(0xFF39D98A);
const Color kSettingsRed = Color(0xFFE5484D);
const Color kSettingsAmber = Color(0xFFF5A623);

/// Thin hairline used for panel borders and row dividers.
final Color kSettingsLine = const Color(0xFFB4A0FF).withValues(alpha: 0.12);
final Color kSettingsDim = Colors.white.withValues(alpha: 0.46);
final Color kSettingsDim2 = Colors.white.withValues(alpha: 0.28);

/// Max content width for the settings column so it doesn't stretch
/// edge-to-edge on TV/desktop.
const double kSettingsMaxWidth = 720;

/// Uniform monochrome initials chip for a connection provider ("RD", "JP").
/// Replaces the old per-provider colored gradient icon boxes — status is
/// carried by the dot/text instead, keeping the chrome calm like Stremio.
String settingsInitialsFor(String title) {
  final words = title
      .split(RegExp(r'[\s&]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  if (words.isEmpty) return '?';
  // Single word: prefer internal capitals (AllDebrid → AD, PikPak → PP).
  final caps = words[0].replaceAll(RegExp(r'[^A-Z]'), '');
  if (caps.length >= 2) return caps.substring(0, 2);
  return words[0].length >= 2
      ? words[0].substring(0, 2).toUpperCase()
      : words[0].toUpperCase();
}

/// Icon + copy for one settings row. Defined once in [SettingsRows] and
/// consumed by BOTH the phone single-column layout and the TV two-pane layout
/// (via `SettingsTile.spec` / `SettingsToggleTile.spec`) so the two can't
/// drift — change a title/icon here and both surfaces update.
class SettingsRowContent {
  final IconData icon;
  final String title;
  final String subtitle;

  /// External link for community rows (Reddit/Discord/GitHub).
  final String? url;

  const SettingsRowContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.url,
  });
}

/// Single source of truth for every settings row's icon + copy.
abstract final class SettingsRows {
  static const homePage = SettingsRowContent(
    icon: Icons.home_rounded,
    title: 'Home Screen',
    subtitle: 'Layout, rows, trailer & continue watching',
  );
  static const collections = SettingsRowContent(
    icon: Icons.collections_bookmark_rounded,
    title: 'Collections',
    subtitle: 'Import Nuvio-style folder collections as Home rows',
  );
  static const player = SettingsRowContent(
    icon: Icons.play_circle_outline_rounded,
    title: 'Playback',
    subtitle: 'Player, skip segments, subtitles, audio & VR',
  );
  static const remote = SettingsRowContent(
    icon: Icons.phonelink_rounded,
    title: 'Remote',
    subtitle: 'Control another device, send or receive setup',
  );
  // The Profiles hub replaced the bare switch action: switching lives on the
  // hub beside the roster, so this row is now the one front door. It heads
  // the Profiles SECTION now (its own card, not a Devices tenant), with the
  // two most-wanted actions surfaced beside it as rows of their own.
  static const switchProfile = SettingsRowContent(
    icon: Icons.switch_account_rounded,
    title: 'Profiles',
    subtitle: 'Who can use this device',
  );
  static const addProfile = SettingsRowContent(
    icon: Icons.person_add_alt_rounded,
    title: 'Add a profile',
    subtitle: 'Admin, Member or Kid',
  );
  static const editProfile = SettingsRowContent(
    icon: Icons.edit_rounded,
    title: 'Edit this profile',
    subtitle: 'Name, avatar, PIN & access',
  );
  static const navigationStyle = SettingsRowContent(
    icon: Icons.call_to_action_rounded,
    title: 'Navigation',
    subtitle: 'Classic bottom bar or floating button',
  );
  static const searchSettings = SettingsRowContent(
    icon: Icons.search_rounded,
    title: 'Engines',
    subtitle: 'Search engine defaults and indexers',
  );
  static const filterSettings = SettingsRowContent(
    icon: Icons.filter_list_rounded,
    title: 'Filters',
    subtitle: 'Default quality, source, and language filters',
  );
  static const providerSettings = SettingsRowContent(
    icon: Icons.cloud_sync_rounded,
    title: 'Default Provider',
    subtitle: 'Where added torrents go',
  );
  static const quickPlay = SettingsRowContent(
    icon: Icons.bolt_rounded,
    title: 'Quick Play',
    subtitle: 'Timeouts, series packs, and cache fallback',
  );
  static const discoverDefault = SettingsRowContent(
    icon: Icons.explore_rounded,
    title: 'Default View',
    subtitle: 'Default source and poster details',
  );
  static const debrifyTv = SettingsRowContent(
    icon: Icons.live_tv_rounded,
    title: 'Debrify TV',
    subtitle: 'Limits, channels, and playback configuration',
  );
  static const recordings = SettingsRowContent(
    icon: Icons.fiber_dvr_rounded,
    title: 'Recordings',
    subtitle: 'Live recordings, schedules, and library',
  );
  static const iptvPlaylists = SettingsRowContent(
    icon: Icons.playlist_play_rounded,
    title: 'IPTV Playlists',
    subtitle: 'Playlists, lists, and startup channel',
  );
  static const tvKeyboard = SettingsRowContent(
    icon: Icons.keyboard_rounded,
    title: 'Debrify Keyboard',
    subtitle: 'Remote-friendly on-screen keyboard for text fields',
  );
  // Subtitle is dynamic (the chosen size) — passed per call site.
  static const tvScreenSize = SettingsRowContent(
    icon: Icons.fit_screen_rounded,
    title: 'Screen Size',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen mode) — passed per call site.
  static const tvRenderQuality = SettingsRowContent(
    icon: Icons.hd_rounded,
    title: 'Rendering',
    subtitle: '',
  );
  static const tvHeroArtworkQuality = SettingsRowContent(
    icon: Icons.photo_size_select_large_rounded,
    title: 'Hero Artwork Quality',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const tvHomeStyle = SettingsRowContent(
    icon: Icons.view_quilt_rounded,
    title: 'Home Layout',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const discoverLayout = SettingsRowContent(
    icon: Icons.explore_rounded,
    title: 'Discover Layout',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const tvSidebarStyle = SettingsRowContent(
    icon: Icons.view_sidebar_rounded,
    title: 'Sidebar Style',
    subtitle: '',
  );
  // The desktop/tablet counterpart — never shown beside the TV row (each is
  // platform-gated), so the shared title is unambiguous wherever it appears.
  static const desktopSidebarStyle = SettingsRowContent(
    icon: Icons.view_sidebar_rounded,
    title: 'Sidebar Style',
    subtitle: '',
  );
  static const profileAppearance = SettingsRowContent(
    icon: Icons.switch_account_rounded,
    title: 'Profile Picker',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen brightness) — passed per call site.
  static const textBrightness = SettingsRowContent(
    icon: Icons.brightness_6_rounded,
    title: 'Text Brightness',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen ident) — passed per call site.
  static const launchAnimation = SettingsRowContent(
    icon: Icons.rocket_launch_rounded,
    title: 'Launch Animation',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const iptvAppearance = SettingsRowContent(
    icon: Icons.style_rounded,
    title: 'IPTV Appearance',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const debrifyTvAppearance = SettingsRowContent(
    icon: Icons.connected_tv_rounded,
    title: 'Debrify TV',
    subtitle: '',
  );
  // Subtitle is dynamic (style + palette) — passed per call site.
  static const playerDock = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Player Controls',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen skin) — passed per call site. Android
  // TV only: the native player's control skin (OTT dock vs Legacy).
  static const tvPlayerControls = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Player Controls',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site. Android
  // TV only: the Debrify TV playback screen (native TorboxTvPlayerActivity).
  static const debrifyTvPlayer = SettingsRowContent(
    icon: Icons.live_tv_rounded,
    title: 'Debrify TV Player',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen look) — passed per call site.
  static const playLoaderStyle = SettingsRowContent(
    icon: Icons.play_circle_outline_rounded,
    title: 'Play Loader',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen style) — passed per call site.
  static const playerGuideStyle = SettingsRowContent(
    icon: Icons.smart_display_rounded,
    title: 'Player Guide',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen layout) — passed per call site.
  static const detailPageStyle = SettingsRowContent(
    icon: Icons.article_rounded,
    title: 'Details Page',
    subtitle: '',
  );
  static const themeLab = SettingsRowContent(
    icon: Icons.science_rounded,
    title: 'Theme Lab',
    subtitle: 'Preview the looks on real widgets',
  );
  // Subtitle is dynamic (the active Look, or "Custom") — passed per call site.
  static const looks = SettingsRowContent(
    icon: Icons.auto_awesome_rounded,
    title: 'Looks',
    subtitle: '',
  );

  /// Sits directly under Looks, in the same section. It was reachable only by
  /// opening Looks first, which put the entire token layer two levels down
  /// behind a row that gave no hint it was there.
  static const themeTokens = SettingsRowContent(
    icon: Icons.tune_rounded,
    title: 'Advanced',
    subtitle: '',
  );
  static const appTheme = SettingsRowContent(
    icon: Icons.format_paint_rounded,
    // Just 'Theme': the section header above it already says THEME, and
    // 'App Theme' only ever needed the qualifier to tell itself apart from
    // the Details Theme row that no longer exists.
    title: 'Theme',
    subtitle: '',
  );
  static const detailTheme = SettingsRowContent(
    icon: Icons.palette_rounded,
    title: 'Details Theme',
    subtitle: '',
  );
  // Subtitle is dynamic (the chosen presentation) — passed per call site.
  static const parentsGuideStyle = SettingsRowContent(
    icon: Icons.family_restroom_rounded,
    title: 'Parents Guide',
    subtitle: '',
  );
  // Subtitle is dynamic (current folder) — passed per call site.
  static const downloadLocation = SettingsRowContent(
    icon: Icons.folder_rounded,
    title: 'Download Location',
    subtitle: '',
  );
  static const clearDownloads = SettingsRowContent(
    icon: Icons.download_rounded,
    title: 'Clear Download Data',
    subtitle: 'Remove queue history and in-progress entries',
  );
  static const clearPlayback = SettingsRowContent(
    icon: Icons.play_circle_rounded,
    title: 'Clear Playback Data',
    subtitle: 'Reset resume points and playback sessions',
  );
  static const createBackup = SettingsRowContent(
    icon: Icons.save_alt_rounded,
    title: 'Create Backup',
    subtitle: 'Save services, addons, and search engines to a file',
  );
  static const restoreBackup = SettingsRowContent(
    icon: Icons.restore_rounded,
    title: 'Restore from Backup',
    subtitle: 'Import services and addons from a backup file',
  );
  static const exportDiagnosticLogs = SettingsRowContent(
    icon: Icons.bug_report_outlined,
    title: 'Export Diagnostic Logs',
    subtitle: 'Save privacy-filtered logs from the last 2 hours',
  );
  static const resetDebrify = SettingsRowContent(
    icon: Icons.warning_rounded,
    title: 'Reset Debrify',
    subtitle: 'Remove connections, preferences, and caches',
  );
  static const autoUpdate = SettingsRowContent(
    icon: Icons.notifications_active_rounded,
    title: 'Auto Check for Updates',
    subtitle: 'Notify about new releases on startup',
  );
  // Subtitle is dynamic (update status) — passed per call site.
  static const checkUpdates = SettingsRowContent(
    icon: Icons.system_update_rounded,
    title: 'Check for Updates',
    subtitle: '',
  );
  static const supportDebrify = SettingsRowContent(
    icon: Icons.favorite_rounded,
    title: 'Support Debrify',
    subtitle: '',
  );
  static const reddit = SettingsRowContent(
    icon: Icons.forum_rounded,
    title: 'Reddit Community',
    subtitle: 'r/debrify - Questions, tips, and discussion',
    url: 'https://www.reddit.com/r/debrify/',
  );
  static const discord = SettingsRowContent(
    icon: Icons.chat_rounded,
    title: 'Discord',
    subtitle: 'Join for help, updates, and discussion',
    url: 'https://discord.gg/xuAc4Q2c9G',
  );
  static const github = SettingsRowContent(
    icon: Icons.code_rounded,
    title: 'GitHub',
    subtitle: 'Source code and contributions',
    url: 'https://github.com/varunsalian/debrify',
  );
  static const version = SettingsRowContent(
    icon: Icons.info_outline_rounded,
    title: 'Version',
    subtitle: '',
  );
}

/// Opens a settings community link. Shared so both layouts launch the same URL.
Future<void> launchSettingsUrl(String url) async {
  await launchUrl(Uri.parse(url));
}

/// Scoped theme for the settings subpages: re-tints every Material widget
/// (inputs, buttons, cards, switches, dialogs, tabs, snackbars…) to the
/// Stremio purple palette so pages restyle wholesale without touching their
/// widget code. Wrap a page's Scaffold in `Theme(data: settingsPageTheme(...))`
/// — or just use [SettingsPageScaffold], which does it for you.
ThemeData settingsPageTheme(BuildContext context) {
  final base = Theme.of(context);
  final app = AppThemeScope.of(context);
  // Memoized: the theme is a pure transform of its two inputs, and rebuilding
  // ~25 sub-theme objects on every page build — including every focus-move
  // setState on TV — is pure waste. BOTH inputs key the cache: a frozen
  // boundary can hand us a legacy ThemeData under a themed app profile (and
  // vice versa), so identity on `base` alone would serve a stale palette.
  if (!identical(base, _settingsThemeBase) ||
      !identical(app, _settingsThemeApp)) {
    _settingsThemeBase = base;
    _settingsThemeApp = app;
    _settingsThemeCache = _buildSettingsPageTheme(base, app);
  }
  return _settingsThemeCache!;
}

ThemeData? _settingsThemeBase;
AppTheme? _settingsThemeApp;
ThemeData? _settingsThemeCache;

ThemeData _buildSettingsPageTheme(ThemeData base, AppTheme app) {
  final t = app.settings;
  // Primary text follows the BASE theme, not a hardcoded white: the base
  // carries the Appearance → Text Brightness preset in its onSurface (white
  // on Bright, so nothing changes there). On-accent colors take `onAccent`,
  // NOT page ink: a label on a FILLED swatch is decided by the swatch, and
  // under legacy that resolves to the same white this used to hardcode.
  final Color text = base.colorScheme.onSurface;
  // Against the SETTINGS accent — the swatch these controls are actually
  // filled with, which under legacy is violet rather than the core's olive.
  final onAccent = app.inkOn(t.accent);
  final scheme = base.colorScheme.copyWith(
    primary: t.accent2,
    onPrimary: onAccent,
    primaryContainer: t.panel2,
    onPrimaryContainer: onAccent,
    secondary: t.accent2,
    onSecondary: onAccent,
    secondaryContainer: t.panel2,
    onSecondaryContainer: onAccent,
    surface: t.bg,
    onSurface: text,
    surfaceContainerHighest: t.panel,
    surfaceContainerHigh: t.panel,
    surfaceContainer: t.panel2,
    surfaceContainerLow: t.panel2,
    error: t.danger,
    outline: const Color(0xFF6E6395),
    outlineVariant: const Color(0xFF3A3158),
    surfaceTint: Colors.transparent,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: text,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: t.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(16),
        side: BorderSide(color: t.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: t.line, thickness: 1),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: t.dim,
      textColor: text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.panel,
      hintStyle: TextStyle(color: t.dim2, fontSize: 13.5),
      labelStyle: TextStyle(color: t.dim, fontSize: 13.5),
      prefixIconColor: t.dim,
      suffixIconColor: t.dim,
      border: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: t.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: t.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: app.shape.br(12),
        borderSide: BorderSide(color: t.danger, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: onAccent,
        disabledBackgroundColor: t.panel2,
        disabledForegroundColor: t.dim2,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: onAccent,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: app.core.tx,
        side: BorderSide(color: const Color(0xFFB4A0FF).withValues(alpha: 0.3)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.accent2,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(10)),
      ),
    ),
    // Disabled states must stay visually distinct (grayed) or users can't
    // tell an inert toggle from an active one — see the hide-from-nav
    // switches, which are disabled until the provider is logged in.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        // The thumb sits ON the track, so SELECTED (an accent track) takes
        // on-accent ink; unselected rides a faint neutral track, where page
        // ink is right. Under legacy both resolve to white, as before.
        final base = states.contains(WidgetState.selected)
            ? onAccent
            : app.core.tx;
        return states.contains(WidgetState.disabled)
            ? base.withValues(alpha: 0.35)
            : base;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final bool selected = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return selected
              ? t.accent.withValues(alpha: 0.3)
              : app.fade(app.core.tx, 0.05);
        }
        return selected ? t.accent : app.fade(app.core.tx, 0.12);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? Colors.transparent : t.line,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return Colors.transparent;
        return states.contains(WidgetState.disabled)
            ? t.accent.withValues(alpha: 0.35)
            : t.accent;
      }),
      side: BorderSide(color: t.dim2, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: app.shape.br(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return app.fade(app.core.tx, 0.18);
        }
        return states.contains(WidgetState.selected) ? t.accent2 : t.dim2;
      }),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: t.accent,
      inactiveTrackColor: app.fade(app.core.tx, 0.12),
      // Rides the ACTIVE (accent) track.
      thumbColor: onAccent,
      overlayColor: t.accent.withValues(alpha: 0.15),
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: t.accent2,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      indicatorColor: t.accent,
      labelColor: text,
      unselectedLabelColor: t.dim,
      dividerColor: t.line,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: t.panel2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(20),
        side: BorderSide(color: t.line),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: t.panel2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(14),
        side: BorderSide(color: t.line),
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: t.panel2,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(backgroundColor: t.panel2),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: app.fade(app.core.tx, 0.06),
      selectedColor: t.accent.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: text, fontSize: 12.5),
      side: BorderSide(color: t.line),
      shape: RoundedRectangleBorder(borderRadius: app.shape.br(10)),
    ),
    dropdownMenuTheme: base.dropdownMenuTheme.copyWith(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.panel2),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: app.shape.br(14),
            side: BorderSide(color: t.line),
          ),
        ),
      ),
    ),
  );
}

/// Pushes a settings subpage wrapped in [settingsPageTheme].
///
/// The wrap must happen at the ROUTE level, not just inside the page:
/// `showDialog` captures InheritedThemes from the *calling* context (the
/// page State's context, which sits above anything the page builds). With
/// the theme applied here, every dialog a settings page opens inherits the
/// purple palette automatically.
Future<T?> pushSettingsPage<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute(
      builder: (ctx) => Theme(data: settingsPageTheme(ctx), child: page),
    ),
  );
}

/// showDialog wrapper that applies [settingsPageTheme] to the dialog even
/// when called from a context above the scoped theme (e.g. the root
/// settings screen, which is a tab, not a pushed settings route).
Future<T?> showSettingsDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => Theme(
      data: settingsPageTheme(ctx),
      child: Builder(builder: builder),
    ),
  );
}

/// Standard scaffold for every settings subpage: applies [settingsPageTheme],
/// paints the [SettingsBackground] wash under a transparent AppBar, and keeps
/// the page's own body/scroll untouched.
class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBarBottom;
  final bool? resizeToAvoidBottomInset;

  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBarBottom,
    this.resizeToAvoidBottomInset,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: settingsPageTheme(context),
      child: SettingsBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          // AppBar chrome (transparent bg, zero elevation) comes from
          // settingsPageTheme.appBarTheme — single source of truth.
          appBar: AppBar(
            title: Text(title),
            leading: leading,
            actions: actions,
            bottom: appBarBottom,
          ),
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
        ),
      ),
    );
  }
}

/// Flat page hero for subpages: accent-tinted icon chip + title + subtitle.
/// Replaces the old gradient `primaryContainer` header cards.
class SettingsPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const SettingsPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: t.accent2, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                // No color: inherits the ambient bodyMedium color, which is
                // onSurface — and so follows Appearance → Text Brightness.
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.dim),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quiet informational banner (replaces the old secondaryContainer info
/// boxes). [tone] tints it: accent (default), warning amber, or danger red.
enum SettingsBannerTone { info, warning, danger, success }

class SettingsInfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final SettingsBannerTone tone;

  const SettingsInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = SettingsBannerTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final Color c = switch (tone) {
      SettingsBannerTone.info => t.accent2,
      SettingsBannerTone.warning => t.warning,
      SettingsBannerTone.danger => t.danger,
      SettingsBannerTone.success => t.success,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: app.shape.br(12),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: app.fade(app.core.tx, 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed settings room.
///
/// The vertical ground-to-pane walk is the same stage used by onboarding.
/// A restrained accent bloom gives themed Looks their identity without
/// returning to the old purple wash that sat behind every theme.
class SettingsBackground extends StatelessWidget {
  final Widget child;
  const SettingsBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (app.id != 'spotlight') {
      return Container(
        color: t.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -1.0),
                    radius: 1.2,
                    colors: [
                      app.fade(t.accent, 0x29 / 0xFF),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.9, 1.1),
                    radius: 1.0,
                    colors: [Color(0x1F4632A0), Colors.transparent],
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      );
    }
    final bottom = Color.lerp(t.bg, app.core.pane, 0.34)!.withValues(alpha: 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.bg.withValues(alpha: 1), bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.92, -1.08),
                  radius: 1.05,
                  colors: [app.fade(t.accent, 0.13), Colors.transparent],
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Backwards-compatible root header used by loading and search surfaces.
/// New responsive roots use [SettingsRootHeader] from the Spotlight shell.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (app.id != 'spotlight') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage connections, search & playback',
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR SPACE',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.1,
            color: t.accent.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Settings',
          // No color: inherits onSurface via the ambient DefaultTextStyle,
          // so it follows Appearance → Text Brightness.
          style: TextStyle(
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Services, screens and playback—tuned in one place.',
          style: TextStyle(fontSize: 12, height: 1.45, color: t.dim),
        ),
      ],
    );
  }
}

/// Quiet uppercase section label ("CONNECTIONS", "GENERAL", …).
class SettingsSectionLabel extends StatelessWidget {
  final String title;
  final Color? color;
  const SettingsSectionLabel(this.title, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final spotlight = app.id == 'spotlight';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: spotlight ? 'JetBrainsMono' : null,
          fontSize: spotlight ? 9 : 12,
          fontWeight: spotlight ? FontWeight.w700 : FontWeight.w800,
          letterSpacing: spotlight ? 1.55 : 0.7,
          color: color ?? app.settings.dim,
        ),
      ),
    );
  }
}

class ConnectionInfo {
  final String title;
  final bool connected;
  final String status;
  final String caption;
  final Future<void> Function() onTap;

  const ConnectionInfo({
    required this.title,
    required this.connected,
    required this.status,
    required this.caption,
    required this.onTap,
  });
}

/// Whether a configured connection is explicitly reporting a degraded state.
///
/// Providers use a few healthy labels (for example `Active` and `Configured`),
/// so treating every non-`Active` value as an error incorrectly marks Jackett
/// and Prowlarr as unhealthy. Only known negative states need intervention.
bool settingsConnectionNeedsAttention(ConnectionInfo info) {
  if (!info.connected) return false;
  final status = info.status.toLowerCase();
  return status.contains('inactive') ||
      status.contains('expired') ||
      status.contains('error') ||
      status.contains('failed') ||
      status.contains('attention');
}

bool settingsConnectionIsReady(ConnectionInfo info) =>
    info.connected && !settingsConnectionNeedsAttention(info);

class ConnectionsSummary extends StatefulWidget {
  final ConnectionInfo realDebrid;
  final ConnectionInfo torbox;
  final ConnectionInfo premiumize;
  final ConnectionInfo allDebrid;
  final ConnectionInfo pikpak;
  final ConnectionInfo webDav;
  final ConnectionInfo indexerManagers;
  final ConnectionInfo iptv;
  final ConnectionInfo trakt;
  final ConnectionInfo simkl;
  final ConnectionInfo tracking;
  // Null when MDBList is hidden (alpha) — its card + focus node are then omitted.
  final ConnectionInfo? mdblist;
  final FocusNode? firstCardFocusNode;

  const ConnectionsSummary({
    super.key,
    required this.realDebrid,
    required this.torbox,
    required this.premiumize,
    required this.allDebrid,
    required this.pikpak,
    required this.webDav,
    required this.indexerManagers,
    required this.iptv,
    required this.trakt,
    required this.simkl,
    required this.tracking,
    this.mdblist,
    this.firstCardFocusNode,
  });

  @override
  State<ConnectionsSummary> createState() => _ConnectionsSummaryState();
}

class _ConnectionsSummaryState extends State<ConnectionsSummary> {
  // Focus nodes for grid navigation
  // Layout (wide) — the Reddit card is hidden (source retired), its
  // ConnectionInfo/focus node are kept so nothing else has to change:
  // [realDebrid,  torbox]
  // [premiumize,  allDebrid]
  // [pikpak,      webDav]
  // [indexerManagers, iptv]
  // [tracking policy]      (full width)
  // [trakt,       simkl]
  // [mdblist]     (alone)
  late final FocusNode _torboxFocusNode;
  late final FocusNode _premiumizeFocusNode;
  late final FocusNode _allDebridFocusNode;
  late final FocusNode _pikpakFocusNode;
  late final FocusNode _webDavFocusNode;
  late final FocusNode _indexerManagersFocusNode;
  late final FocusNode _iptvFocusNode;
  late final FocusNode _trackingFocusNode;
  late final FocusNode _traktFocusNode;
  late final FocusNode _simklFocusNode;
  late final FocusNode _mdblistFocusNode;

  @override
  void initState() {
    super.initState();
    _torboxFocusNode = FocusNode(debugLabel: 'settings-torbox');
    _premiumizeFocusNode = FocusNode(debugLabel: 'settings-premiumize');
    _allDebridFocusNode = FocusNode(debugLabel: 'settings-alldebrid');
    _pikpakFocusNode = FocusNode(debugLabel: 'settings-pikpak');
    _webDavFocusNode = FocusNode(debugLabel: 'settings-webdav');
    _indexerManagersFocusNode = FocusNode(
      debugLabel: 'settings-indexer-managers',
    );
    _iptvFocusNode = FocusNode(debugLabel: 'settings-iptv');
    _trackingFocusNode = FocusNode(debugLabel: 'settings-tracking');
    _traktFocusNode = FocusNode(debugLabel: 'settings-trakt');
    _simklFocusNode = FocusNode(debugLabel: 'settings-simkl');
    _mdblistFocusNode = FocusNode(debugLabel: 'settings-mdblist');
  }

  @override
  void dispose() {
    _torboxFocusNode.dispose();
    _premiumizeFocusNode.dispose();
    _allDebridFocusNode.dispose();
    _pikpakFocusNode.dispose();
    _webDavFocusNode.dispose();
    _indexerManagersFocusNode.dispose();
    _iptvFocusNode.dispose();
    _trackingFocusNode.dispose();
    _traktFocusNode.dispose();
    _simklFocusNode.dispose();
    _mdblistFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionLabel('Connections'),
        LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth > 520;
            final double itemWidth = wide
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            // Grid layout (wide) — Reddit card hidden, source retired:
            // [RD]         [Torbox]
            // [Premiumize] [AllDebrid]
            // [PikPak]     [WebDAV]
            // [Indexers]   [IPTV]
            // ── Tracking ──
            // [cross-service policy]
            // ── Tracker services ──
            // [Trakt]       [Simkl]
            // [MDBList]
            //
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Real Debrid (left), Torbox (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.realDebrid,
                        focusNode: widget.firstCardFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _torboxFocusNode : null,
                        downNeighbor: wide
                            ? _premiumizeFocusNode
                            : _torboxFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.torbox,
                        focusNode: _torboxFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? widget.firstCardFocusNode : null,
                        upNeighbor: wide ? null : widget.firstCardFocusNode,
                        downNeighbor: wide
                            ? _allDebridFocusNode
                            : _premiumizeFocusNode,
                      ),
                    ),
                    // Row 2: Premiumize (left), AllDebrid (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.premiumize,
                        focusNode: _premiumizeFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _allDebridFocusNode : null,
                        upNeighbor: wide
                            ? widget.firstCardFocusNode
                            : _torboxFocusNode,
                        downNeighbor: wide
                            ? _pikpakFocusNode
                            : _allDebridFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.allDebrid,
                        focusNode: _allDebridFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _premiumizeFocusNode : null,
                        upNeighbor: wide
                            ? _torboxFocusNode
                            : _premiumizeFocusNode,
                        downNeighbor: wide
                            ? _webDavFocusNode
                            : _pikpakFocusNode,
                      ),
                    ),
                    // Row 3: PikPak (left), WebDAV (right)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.pikpak,
                        focusNode: _pikpakFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _webDavFocusNode : null,
                        upNeighbor: wide
                            ? _premiumizeFocusNode
                            : _allDebridFocusNode,
                        downNeighbor: wide
                            ? _indexerManagersFocusNode
                            : _webDavFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.webDav,
                        focusNode: _webDavFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _pikpakFocusNode : null,
                        upNeighbor: wide
                            ? _allDebridFocusNode
                            : _pikpakFocusNode,
                        downNeighbor: wide
                            ? _iptvFocusNode
                            : _indexerManagersFocusNode,
                      ),
                    ),
                    // Row 4: Indexer managers (left), IPTV (right).
                    // (The retired Reddit source's card, params and focus
                    // node were removed with its orphaned settings page.)
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.indexerManagers,
                        focusNode: _indexerManagersFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _iptvFocusNode : null,
                        upNeighbor: wide ? _pikpakFocusNode : _webDavFocusNode,
                        downNeighbor: wide
                            ? _trackingFocusNode
                            : _iptvFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.iptv,
                        focusNode: _iptvFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _indexerManagersFocusNode : null,
                        upNeighbor: wide
                            ? _webDavFocusNode
                            : _indexerManagersFocusNode,
                        downNeighbor: _trackingFocusNode,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const SettingsSectionLabel('Tracking'),
                SizedBox(
                  width: constraints.maxWidth,
                  child: ConnectionCard(
                    info: widget.tracking,
                    focusNode: _trackingFocusNode,
                    isLeftColumn: true,
                    upNeighbor: wide
                        ? _indexerManagersFocusNode
                        : _iptvFocusNode,
                    downNeighbor: _traktFocusNode,
                  ),
                ),
                const SizedBox(height: 22),
                const SettingsSectionLabel('Tracker services'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    // Row 1: Trakt (left), Simkl (right).
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.trakt,
                        focusNode: _traktFocusNode,
                        isLeftColumn: true,
                        rightNeighbor: wide ? _simklFocusNode : null,
                        upNeighbor: _trackingFocusNode,
                        downNeighbor: wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : _simklFocusNode,
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: ConnectionCard(
                        info: widget.simkl,
                        focusNode: _simklFocusNode,
                        isLeftColumn: !wide,
                        leftNeighbor: wide ? _traktFocusNode : null,
                        upNeighbor: wide ? _trackingFocusNode : _traktFocusNode,
                        downNeighbor: !wide && widget.mdblist != null
                            ? _mdblistFocusNode
                            : null,
                      ),
                    ),
                    // Row 2: MDBList (left, when enabled).
                    if (widget.mdblist != null)
                      SizedBox(
                        width: itemWidth,
                        child: ConnectionCard(
                          info: widget.mdblist!,
                          focusNode: _mdblistFocusNode,
                          isLeftColumn: true,
                          upNeighbor: wide ? _traktFocusNode : _simklFocusNode,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Flat provider row: mono initials chip · name + caption · status dot + text
/// · chevron. Focus/hover paints the accent ring, Stremio-style.
///
/// The manual DPAD neighbor wiring (and the sidebar hand-off on left from the
/// left column) is preserved verbatim from the original card — do not swap it
/// for default traversal without testing on real TV hardware.
class ConnectionCard extends StatefulWidget {
  final ConnectionInfo info;
  final FocusNode? focusNode;
  final bool isLeftColumn;
  final FocusNode? leftNeighbor;
  final FocusNode? rightNeighbor;
  final FocusNode? upNeighbor;
  final FocusNode? downNeighbor;

  const ConnectionCard({
    super.key,
    required this.info,
    this.focusNode,
    this.isLeftColumn = true,
    this.leftNeighbor,
    this.rightNeighbor,
    this.upNeighbor,
    this.downNeighbor,
  });

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  /// The wrapper's own node, so focus can be read rather than remembered —
  /// see the note on `_SettingsTileState._focused`.
  final FocusNode _wrapNode = FocusNode(debugLabel: 'ConnectionCard');

  bool _hovered = false;

  /// Live, never cached. `hasFocus` is DESCENDANT-inclusive, so this wrapper
  /// reads true while the card's own InkWell below it holds focus — which is
  /// the intent, and the same value `Focus.onFocusChange` used to deliver.
  bool get _focused => _wrapNode.hasFocus;

  /// The theme's tempo, resolved in the one hook that may depend on inherited
  /// widgets and still re-runs when they change. The reveal below fires from a
  /// key handler, which is no place for a scope lookup.
  late AppMotion _motion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion = AppMotion.of(context);
  }

  @override
  void dispose() {
    _wrapNode.dispose();
    super.dispose();
  }

  // Helper to focus and scroll into view
  void _focusAndScroll(FocusNode target) {
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target.context != null) {
        tvRevealMinimal(
          target.context!,
          duration: _motion.scaled(const Duration(milliseconds: 200)),
        );
      }
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (widget.leftNeighbor != null) {
        _focusAndScroll(widget.leftNeighbor!);
        return KeyEventResult.handled;
      } else if (widget.isLeftColumn && MainPageBridge.focusTvSidebar != null) {
        // Left column with no left neighbor: open sidebar
        MainPageBridge.focusTvSidebar!();
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (widget.rightNeighbor != null) {
        _focusAndScroll(widget.rightNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (widget.upNeighbor != null) {
        _focusAndScroll(widget.upNeighbor!);
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (widget.downNeighbor != null) {
        _focusAndScroll(widget.downNeighbor!);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final info = widget.info;
    final bool active = settingsConnectionIsReady(info);
    // One color for both the dot and the status text so they can't disagree.
    final Color baseStateColor = info.connected
        ? (active ? t.success : t.danger)
        : t.dim2;
    final bool lit = _focused || _hovered;
    final bool spotlight = app.id == 'spotlight';
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color stateColor = inverse
        ? Color.lerp(baseStateColor, foreground, 0.42)!
        : baseStateColor;
    final radius = spotlight ? app.shape.br(13) : BorderRadius.circular(14);

    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Focus(
        focusNode: _wrapNode,
        onKeyEvent: _onKeyEvent,
        // hasFocus includes the InkWell child node, so this lights up when the
        // card's InkWell receives DPAD focus.
        onFocusChange: (_) => setState(() {}),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          // Plain Container (snap, no tween): animating a blurred BoxShadow
          // re-rasterizes per frame and janks weak TV GPUs (see
          // tv_sidebar_nav.dart for the same rule).
          child: Container(
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : (lit
                        ? t.panel2
                        : spotlight
                        ? app.fade(app.core.tx, 0.047)
                        : t.panel),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : (_focused ? t.accent : t.line),
                width: 1,
              ),
              boxShadow: _focused && !inverse
                  ? [
                      BoxShadow(
                        color: t.accent.withValues(alpha: 0.28),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                focusNode: widget.focusNode,
                borderRadius: radius,
                onTap: () async {
                  await info.onTap();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: inverse
                              ? foreground.withValues(alpha: 0.08)
                              : app.fade(
                                  app.core.tx,
                                  spotlight ? 0.065 : 0.055,
                                ),
                          borderRadius: app.shape.br(11),
                          border: Border.all(
                            color: inverse
                                ? foreground.withValues(alpha: 0.1)
                                : t.line,
                          ),
                        ),
                        child: Text(
                          settingsInitialsFor(info.title),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: inverse
                                ? foreground
                                : (lit ? t.accent2 : t.dim),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: spotlight
                                    ? foreground
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              info.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: inverse
                                    ? foreground.withValues(alpha: 0.5)
                                    : t.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: stateColor,
                          shape: BoxShape.circle,
                          boxShadow: active
                              ? [
                                  BoxShadow(
                                    color: stateColor.withValues(alpha: 0.55),
                                    blurRadius: 7,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        info.status,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: stateColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat panel section: quiet uppercase label above a bordered panel of rows
/// separated by hairlines.
class SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? accentColor;

  /// One line under the header saying what the rows below have in common.
  ///
  /// Optional because most sections are self-evident from their title. It
  /// earns its place where a group's rows LOOK like their neighbours but
  /// answer a different question — Appearance's performance rows next to its
  /// style rows being the case that prompted it.
  final String? blurb;

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.accentColor,
    this.blurb,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    // The `settingsGroup` family, and the reason it is capped to fill-or-rule:
    // this is ONE filled container whose rows have zero inter-row gap and an
    // in-place `Border.all`. Dropping both would shift every row by a pixel
    // and dissolve the grouping into an undifferentiated stack — so `space`
    // and `glass` are not on offer, and a look that asks for either is
    // clamped to `rule` by `modelFor` before it reaches here.
    final rule =
        app.surface.modelFor(SurfaceFamily.settingsGroup) ==
        SeparationModel.rule;
    final spotlight = app.id == 'spotlight';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SettingsSectionLabel(title, color: accentColor),
        if (blurb != null)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10, right: 8),
            child: Text(
              blurb!,
              style: TextStyle(fontSize: 12, height: 1.4, color: t.dim),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            // A rule look keeps the border — that IS its separation — and
            // loses only the fill. The border width is unchanged either way,
            // which is what keeps the row geometry identical.
            color: rule
                ? Colors.transparent
                : spotlight
                ? app.fade(app.core.tx, app.isLight ? 0.035 : 0.047)
                : t.panel,
            borderRadius: spotlight
                ? app.shape.br(13)
                : BorderRadius.circular(16),
            border: Border.all(color: t.line, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i != 0) Divider(height: 1, thickness: 1, color: t.line),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Prominent active-Look row used at the top of Appearance.
///
/// A Look changes several downstream controls at once, so presenting it as
/// one more 52dp row understated its effect and made Appearance read as an
/// arbitrary list. The swatches are derived from the active theme itself.
class SettingsLookHero extends StatefulWidget {
  const SettingsLookHero({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.focusNode,
  });

  final String label;
  final String subtitle;
  final Future<void> Function() onTap;
  final FocusNode? focusNode;

  @override
  State<SettingsLookHero> createState() => _SettingsLookHeroState();
}

class _SettingsLookHeroState extends State<SettingsLookHero> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final lit = _focused || _hovered;
    final inverse = lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(13);
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (value) => setState(() => _hovered = value),
          onTap: () async => await widget.onTap(),
          borderRadius: radius,
          child: Container(
            constraints: const BoxConstraints(minHeight: 116),
            padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 18),
            decoration: BoxDecoration(
              color: inverse
                  ? app.core.tx
                  : Color.alphaBlend(
                      t.accent.withValues(alpha: 0.1),
                      app.fade(app.core.tx, 0.04),
                    ),
              borderRadius: radius,
              border: Border.all(
                color: inverse ? app.core.tx : t.accent.withValues(alpha: 0.24),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSwatches = constraints.maxWidth >= 390;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ACTIVE LOOK',
                            style: TextStyle(
                              fontFamily: 'JetBrainsMono',
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.55,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.6)
                                  : t.accent2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: foreground,
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1.4,
                              color: inverse
                                  ? foreground.withValues(alpha: 0.5)
                                  : t.dim,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (showSwatches) ...[
                      const SizedBox(width: 20),
                      _SettingsSwatches(inverse: inverse),
                    ],
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: inverse
                          ? foreground.withValues(alpha: 0.42)
                          : t.dim2,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSwatches extends StatelessWidget {
  const _SettingsSwatches({required this.inverse});

  final bool inverse;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final colors = [
      app.core.ground,
      app.core.pane,
      app.settings.accent,
      app.core.tx,
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < colors.length; i++) ...[
          Container(
            width: 25,
            height: 42,
            decoration: BoxDecoration(
              color: colors[i],
              borderRadius: app.shape.br(7),
              border: Border.all(
                color: inverse
                    ? app.inkOn(app.core.tx).withValues(alpha: 0.12)
                    : app.settings.line,
              ),
            ),
          ),
          if (i != colors.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

/// Flat settings row: mono icon · title + subtitle · chevron (or custom
/// trailing). Focus/hover lights the row with the accent ring so DPAD focus
/// is unmissable on TV.
class SettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final String? tag;
  final Widget? trailing;

  /// Renders the icon and title in the destructive red (Danger Zone).
  final bool destructive;

  /// False greys the whole row out and makes it inert: no tap, no hover
  /// light, and DPAD traversal skips it. The subtitle stays readable — a
  /// disabled row should say WHY it's disabled (e.g. "Only used by the
  /// Spotlight layout") rather than vanish.
  final bool enabled;

  /// Lets a parent (e.g. the TV two-pane rail) drive focus onto this row.
  final FocusNode? focusNode;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
    this.trailing,
    this.destructive = false,
    this.enabled = true,
    this.focusNode,
  });

  /// Build from a shared [SettingsRowContent] so the TV and phone layouts
  /// stay in lockstep. [subtitle] overrides the content's (for dynamic rows
  /// like "Check for Updates").
  factory SettingsTile.spec(
    SettingsRowContent content, {
    Key? key,
    required Future<void> Function() onTap,
    String? subtitle,
    String? tag,
    Widget? trailing,
    bool destructive = false,
    bool enabled = true,
    FocusNode? focusNode,
  }) {
    return SettingsTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: subtitle ?? content.subtitle,
      onTap: onTap,
      tag: tag,
      trailing: trailing,
      destructive: destructive,
      enabled: enabled,
      focusNode: focusNode,
    );
  }

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  /// Owned only when the caller did not supply one.
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Read LIVE from the node, never cached from `onFocusChange`.
  ///
  /// A cached bool is only as good as the callback that maintains it, and
  /// Flutter does not guarantee the falling edge: pop a route that was opened
  /// with OK and focus is restored to the MODAL SCOPE rather than to a row, so
  /// the rows that were focus-walked on the way in are never told they lost
  /// it. They keep their cached `true`, and under the Spotlight look that is
  /// not a faint stale highlight — every one of them paints a solid white
  /// plate, so the list comes back from a sub-page with two or three cursors
  /// on it and no way to tell which row OK will open.
  ///
  /// Derived state cannot go stale the way a remembered one does: the value is
  /// re-read on every build, so it is only ever as old as the last rebuild
  /// rather than as old as the last callback that arrived.
  ///
  /// Being precise about what that does and does not buy, because the
  /// difference matters if this is ever revisited: the repaint trigger is
  /// still the same `onFocusChange` the bug rides on, so a silently-missed
  /// notification leaves the WRONG PIXELS up until something rebuilds this
  /// row — it does not repaint it the instant focus leaves. What reliably
  /// rebuilds it is the row's own `onTap` being awaited below: callers
  /// setState when the pushed page returns, which rebuilds the list with
  /// fresh values. (A route transition alone would NOT do it — ModalScope
  /// caches the page subtree behind its AnimatedBuilder's `child`.)
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final bool lit = widget.enabled && (_focused || _hovered);
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final Color foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final Color iconColor = widget.destructive
        ? (inverse ? Color.lerp(t.danger, foreground, 0.38)! : t.danger)
        : (inverse ? foreground : (lit ? t.accent2 : t.dim));
    final radius = app.shape.br(12);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focused ? t.accent : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: _node,
          // Also drops the row out of DPAD traversal — an unfocusable node
          // never enters the traversal ring, so no remote step is eaten.
          canRequestFocus: widget.enabled,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: widget.enabled
              ? () async {
                  await widget.onTap();
                }
              : null,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            // One veil for the whole anatomy (icon, tag chip, chevron) rather
            // than per-part disabled colors that would drift out of sync.
            child: Opacity(
              opacity: widget.enabled ? 1 : 0.45,
              child: Row(
                children: [
                  if (spotlight)
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: inverse
                            ? foreground.withValues(alpha: 0.08)
                            : app.fade(app.core.tx, 0.055),
                        borderRadius: app.shape.br(10),
                      ),
                      child: Icon(widget.icon, color: iconColor, size: 20),
                    )
                  else
                    SizedBox(
                      width: 34,
                      child: Icon(widget.icon, color: iconColor, size: 22),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: widget.destructive
                                      ? t.danger
                                      : spotlight
                                      ? foreground
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  widget.tag!,
                                  style: TextStyle(
                                    color: inverse
                                        ? Color.lerp(t.accent, foreground, 0.25)
                                        : t.accent2,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9.5,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: inverse
                                ? foreground.withValues(alpha: 0.5)
                                : t.dim,
                          ),
                        ),
                      ],
                    ),
                  ),
                  widget.trailing ??
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: inverse
                            ? foreground.withValues(alpha: 0.42)
                            : t.dim2,
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

/// Flat toggle row — same anatomy as [SettingsTile] with a switch on the
/// right instead of a chevron.
class SettingsToggleTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final FocusNode? focusNode;
  final int subtitleMaxLines;

  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.focusNode,
    this.subtitleMaxLines = 1,
  });

  factory SettingsToggleTile.spec(
    SettingsRowContent content, {
    Key? key,
    required bool value,
    required ValueChanged<bool> onChanged,
    FocusNode? focusNode,
    int subtitleMaxLines = 1,
  }) {
    return SettingsToggleTile(
      key: key,
      icon: content.icon,
      title: content.title,
      subtitle: content.subtitle,
      value: value,
      onChanged: onChanged,
      focusNode: focusNode,
      subtitleMaxLines: subtitleMaxLines,
    );
  }

  @override
  State<SettingsToggleTile> createState() => _SettingsToggleTileState();
}

class _SettingsToggleTileState extends State<SettingsToggleTile> {
  FocusNode? _ownNode;
  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  bool _hovered = false;

  /// Live, never cached — see the note on `_SettingsTileState._focused`.
  bool get _focused => _node.hasFocus;

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final bool lit = _focused || _hovered;
    final bool inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(12);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return ParallaxFocus(
      focused: _focused,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focused ? t.accent : Colors.transparent),
            width: 1,
          ),
        ),
        child: InkWell(
          focusNode: _node,
          onFocusChange: (_) => setState(() {}),
          onHover: (h) => setState(() => _hovered = h),
          onTap: () => widget.onChanged(!widget.value),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(
              children: [
                if (spotlight)
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inverse
                          ? foreground.withValues(alpha: 0.08)
                          : app.fade(app.core.tx, 0.055),
                      borderRadius: app.shape.br(10),
                    ),
                    child: Icon(
                      widget.icon,
                      color: inverse ? foreground : (lit ? t.accent2 : t.dim),
                      size: 20,
                    ),
                  )
                else
                  SizedBox(
                    width: 34,
                    child: Icon(
                      widget.icon,
                      color: lit ? t.accent2 : t.dim,
                      size: 22,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: spotlight
                              ? foreground
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: widget.subtitleMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: inverse
                              ? foreground.withValues(alpha: 0.5)
                              : t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
                // The row's InkWell is the single DPAD stop; a focusable
                // Switch would make every toggle cost two presses on TV.
                ExcludeFocus(
                  child: Switch.adaptive(
                    value: widget.value,
                    onChanged: widget.onChanged,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One Android TV "Screen Size" choice. [percent] is the share of the panel's
/// native density the UI is laid out at — smaller means a wider logical canvas,
/// so the same layouts draw smaller and more fits on screen. Values must stay in
/// step with `StorageService.kTvUiScaleOptions`; the shipped default is
/// `StorageService.kTvUiScaleDefault`.
///
/// Lives here (not in the TV settings shell) because two surfaces render it:
/// the TV Mode rail row's caption and the Screen Size page itself.
class TvUiScaleChoice {
  final int percent;
  final String title;
  final String subtitle;
  const TvUiScaleChoice(this.percent, this.title, this.subtitle);

  /// "Compact (80%)" — the row caption and the page's selected label.
  String get label => '$title ($percent%)';
}

const List<TvUiScaleChoice> kTvUiScaleChoices = [
  TvUiScaleChoice(100, 'Large', 'The original size — everything bigger'),
  TvUiScaleChoice(90, 'Medium', 'Default — about 10% more fits on screen'),
  TvUiScaleChoice(80, 'Compact', 'About 25% more fits on screen'),
];

/// Caption for [percent], falling back to the raw value if a stored size is
/// ever outside the offered set.
String tvUiScaleLabel(int percent) {
  for (final c in kTvUiScaleChoices) {
    if (c.percent == percent) return c.label;
  }
  return '$percent%';
}

/// One entry in the Android TV "Rendering" picker.
class TvRenderQualityChoice {
  final TvRenderQuality quality;
  final String label;
  final String subtitle;
  const TvRenderQualityChoice(this.quality, this.label, this.subtitle);
}

/// Automatic first: it's the default, and it's the only option that leaves the
/// device-capability call intact. The other two are named for the TRADE, not
/// for the mechanism — nobody browsing settings knows what a render buffer is,
/// but everybody knows which of "sharper" and "smoother" they want right now.
const List<TvRenderQualityChoice> kTvRenderQualityChoices = [
  TvRenderQualityChoice(
    TvRenderQuality.auto,
    'Automatic',
    "Default — Debrify picks based on this TV's graphics",
  ),
  TvRenderQualityChoice(
    TvRenderQuality.sharp,
    'Sharper picture',
    'Draw at the panel\'s full resolution',
  ),
  TvRenderQualityChoice(
    TvRenderQuality.fast,
    'Smoother navigation',
    'Draw at about 720p so scrolling stays fluid — text and art look softer',
  ),
];

/// Caption for [quality] — the settings row's subtitle and the picker's
/// selected label.
String tvRenderQualityLabel(TvRenderQuality quality) {
  for (final c in kTvRenderQualityChoices) {
    if (c.quality == quality) return c.label;
  }
  return 'Automatic';
}

/// One choice inside a [SettingsSelectDropdown].
class SettingsSelectOption {
  final String value;
  final String title;
  final String? subtitle;

  const SettingsSelectOption(this.value, this.title, [this.subtitle]);
}

/// Single-choice dropdown for settings cards — replaces the old
/// RadioListTile stacks (Post-Torrent Action, File Selection, …).
///
/// DPAD notes: the closed field is one focusable node (focus ring comes from
/// the themed `focusedBorder`); OK opens the menu, whose items take DPAD
/// focus natively, and BACK dismisses it. The selected option's subtitle is
/// echoed under the field so the descriptive copy isn't lost when closed.
class SettingsSelectDropdown extends StatelessWidget {
  final List<SettingsSelectOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;

  const SettingsSelectDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final SettingsSelectOption? selected = options
        .cast<SettingsSelectOption?>()
        .firstWhere((o) => o!.value == value, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          focusNode: focusNode,
          // A stale stored value (e.g. removed option) renders as an empty
          // field instead of tripping DropdownButton's value assert.
          initialValue: selected?.value,
          isExpanded: true,
          // Variable item heights so subtitles fit in the open menu.
          itemHeight: null,
          dropdownColor: t.panel2,
          borderRadius: BorderRadius.circular(14),
          // No focusColor: with an InputDecoration the SDK swaps the fill
          // color for it on focus, which would blank the panel fill. Focus
          // is carried by the themed focusedBorder instead.
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.dim),
          decoration: const InputDecoration(),
          // Explicit color (not inherit): the dropdown renders its menu items
          // with this style directly, outside the page's DefaultTextStyle.
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          // Closed field shows just the title; the subtitle lives below.
          selectedItemBuilder: (context) => [
            for (final o in options)
              Align(alignment: Alignment.centerLeft, child: Text(o.title)),
          ],
          items: [
            for (final o in options)
              DropdownMenuItem<String>(
                value: o.value,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        o.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: o.value == value
                              ? t.accent2
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (o.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: t.dim,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
        if (selected?.subtitle != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              selected!.subtitle!,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: t.dim),
            ),
          ),
        ],
      ],
    );
  }
}

/// Non-interactive key/value row (e.g. Version).
class SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  factory SettingsInfoTile.spec(
    SettingsRowContent content, {
    Key? key,
    required String value,
  }) {
    return SettingsInfoTile(
      key: key,
      icon: content.icon,
      title: content.title,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: t.dim, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              // No color: inherits onSurface (Text Brightness).
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: app.fade(app.core.tx, 0.05),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.line),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading skeleton, restyled to the flat Stremio panels.
class SettingsSkeleton extends StatelessWidget {
  const SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsBackground(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SkeletonHeader(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
                SizedBox(height: 24),
                _SkeletonSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Shimmer(width: 140, height: 24),
        SizedBox(height: 10),
        Shimmer(width: 220, height: 13),
      ],
    );
  }
}

class _SkeletonSection extends StatelessWidget {
  const _SkeletonSection();

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 120, height: 12),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: t.panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.line),
          ),
          child: Column(
            children: [
              const _SkeletonTile(),
              Divider(height: 1, color: t.line),
              const _SkeletonTile(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: const [
          Shimmer(
            width: 34,
            height: 34,
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          SizedBox(width: 12),
          Expanded(child: Shimmer(height: 14)),
        ],
      ),
    );
  }
}

/// The "why is this install in legacy mode" dialog, opened from the Profiles
/// row on every settings layout.
///
/// This dialog IS the bug report. The one channel a television reporter
/// reliably has is a phone photo of the screen, so the captured reason —
/// including the error and its first stack frame on the unpredicted path —
/// is shown in full here rather than summarized. The reassurance lines are
/// as load-bearing as the diagnosis: legacy mode looks like data loss from
/// the couch, and it is precisely the opposite.
Future<void> showLegacyModeInfoDialog(BuildContext context) {
  final app = AppThemeScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: app.sheetSurface,
      title: const Text('Running in legacy mode'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ProfileBootstrap.legacyReasonSummary,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: app.core.tx,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your data is untouched — migration copies, never moves — and '
                'it retries automatically on every launch.\n\n'
                'If this keeps appearing, photograph this dialog and share it '
                'in the Discord: the text above identifies the cause.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: app.core.tx.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
