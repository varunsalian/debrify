import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../services/main_page_bridge.dart';
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
    title: 'Home Page',
    subtitle: 'Default view when app opens',
  );
  static const player = SettingsRowContent(
    icon: Icons.open_in_new_rounded,
    title: 'Player Settings',
    subtitle: 'Configure preferred video player',
  );
  static const remote = SettingsRowContent(
    icon: Icons.phonelink_rounded,
    title: 'Remote',
    subtitle: 'Send setup or receive from another device',
  );
  static const searchSettings = SettingsRowContent(
    icon: Icons.search_rounded,
    title: 'Search Settings',
    subtitle: 'Engines, filters, and sorting',
  );
  static const filterSettings = SettingsRowContent(
    icon: Icons.filter_list_rounded,
    title: 'Filter Settings',
    subtitle: 'Default quality, source, and language filters',
  );
  static const providerSettings = SettingsRowContent(
    icon: Icons.cloud_sync_rounded,
    title: 'Provider Settings',
    subtitle: 'Default provider for adding torrents',
  );
  static const quickPlay = SettingsRowContent(
    icon: Icons.bolt_rounded,
    title: 'Quick Play Settings',
    subtitle: 'Configure quick play for torrent search',
  );
  static const debrifyTv = SettingsRowContent(
    icon: Icons.live_tv_rounded,
    title: 'Debrify TV Settings',
    subtitle: 'Limits, channels, and playback configuration',
  );
  static const tvKeyboard = SettingsRowContent(
    icon: Icons.keyboard_rounded,
    title: 'Debrify Keyboard',
    subtitle: 'Remote-friendly on-screen keyboard for text fields',
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
  // Memoized: the theme is a pure transform of the (static) app theme, and
  // rebuilding ~25 sub-theme objects on every page build — including every
  // focus-move setState on TV — is pure waste.
  if (!identical(base, _settingsThemeBase)) {
    _settingsThemeBase = base;
    _settingsThemeCache = _buildSettingsPageTheme(base);
  }
  return _settingsThemeCache!;
}

ThemeData? _settingsThemeBase;
ThemeData? _settingsThemeCache;

ThemeData _buildSettingsPageTheme(ThemeData base) {
  final scheme = base.colorScheme.copyWith(
    primary: kSettingsAccent2,
    onPrimary: Colors.white,
    primaryContainer: kSettingsPanel2,
    onPrimaryContainer: Colors.white,
    secondary: kSettingsAccent2,
    onSecondary: Colors.white,
    secondaryContainer: kSettingsPanel2,
    onSecondaryContainer: Colors.white,
    surface: kSettingsBg,
    onSurface: Colors.white,
    surfaceContainerHighest: kSettingsPanel,
    surfaceContainerHigh: kSettingsPanel,
    surfaceContainer: kSettingsPanel2,
    surfaceContainerLow: kSettingsPanel2,
    error: kSettingsRed,
    outline: const Color(0xFF6E6395),
    outlineVariant: const Color(0xFF3A3158),
    surfaceTint: Colors.transparent,
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: kSettingsBg,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
        color: Colors.white,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: kSettingsPanel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kSettingsLine),
      ),
    ),
    dividerTheme: DividerThemeData(color: kSettingsLine, thickness: 1),
    listTileTheme: base.listTileTheme.copyWith(
      iconColor: kSettingsDim,
      textColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSettingsPanel,
      hintStyle: TextStyle(color: kSettingsDim2, fontSize: 13.5),
      labelStyle: TextStyle(color: kSettingsDim, fontSize: 13.5),
      prefixIconColor: kSettingsDim,
      suffixIconColor: kSettingsDim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kSettingsLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kSettingsLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSettingsAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSettingsRed, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSettingsRed, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kSettingsAccent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: kSettingsPanel2,
        disabledForegroundColor: kSettingsDim2,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kSettingsAccent,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: const Color(0xFFB4A0FF).withValues(alpha: 0.3)),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: kSettingsAccent2,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    // Disabled states must stay visually distinct (grayed) or users can't
    // tell an inert toggle from an active one — see the hide-from-nav
    // switches, which are disabled until the provider is logged in.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? Colors.white.withValues(alpha: 0.35)
            : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith((states) {
        final bool selected = states.contains(WidgetState.selected);
        if (states.contains(WidgetState.disabled)) {
          return selected
              ? kSettingsAccent.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.05);
        }
        return selected
            ? kSettingsAccent
            : Colors.white.withValues(alpha: 0.12);
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : kSettingsLine,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (!states.contains(WidgetState.selected)) return Colors.transparent;
        return states.contains(WidgetState.disabled)
            ? kSettingsAccent.withValues(alpha: 0.35)
            : kSettingsAccent;
      }),
      side: BorderSide(color: kSettingsDim2, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return Colors.white.withValues(alpha: 0.18);
        }
        return states.contains(WidgetState.selected)
            ? kSettingsAccent2
            : kSettingsDim2;
      }),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: kSettingsAccent,
      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
      thumbColor: Colors.white,
      overlayColor: kSettingsAccent.withValues(alpha: 0.15),
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: kSettingsAccent2,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      indicatorColor: kSettingsAccent,
      labelColor: Colors.white,
      unselectedLabelColor: kSettingsDim,
      dividerColor: kSettingsLine,
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: kSettingsPanel2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: kSettingsLine),
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: kSettingsPanel2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kSettingsLine),
      ),
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: kSettingsPanel2,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: kSettingsPanel2,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      selectedColor: kSettingsAccent.withValues(alpha: 0.25),
      labelStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      side: BorderSide(color: kSettingsLine),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dropdownMenuTheme: base.dropdownMenuTheme.copyWith(
      menuStyle: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(kSettingsPanel2),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: kSettingsLine),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: kSettingsAccent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kSettingsAccent2, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: kSettingsDim,
                ),
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
    final Color c = switch (tone) {
      SettingsBannerTone.info => kSettingsAccent2,
      SettingsBannerTone.warning => kSettingsAmber,
      SettingsBannerTone.danger => kSettingsRed,
      SettingsBannerTone.success => kSettingsGreen,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
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
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed Stremio-dark background with two soft purple radial washes,
/// matching the Discover board's ambience.
class SettingsBackground extends StatelessWidget {
  final Widget child;
  const SettingsBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSettingsBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.85, -1.0),
                  radius: 1.2,
                  colors: [Color(0x297B5CFF), Colors.transparent],
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
}

/// Flat page header: bold title + quiet subtitle. Replaces the old gradient
/// hero card.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manage connections, search & playback',
          style: TextStyle(fontSize: 13, color: kSettingsDim),
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
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: color ?? kSettingsDim,
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

class ConnectionsSummary extends StatefulWidget {
  final ConnectionInfo realDebrid;
  final ConnectionInfo torbox;
  final ConnectionInfo premiumize;
  final ConnectionInfo allDebrid;
  final ConnectionInfo pikpak;
  final ConnectionInfo webDav;
  final ConnectionInfo indexerManagers;
  final ConnectionInfo reddit;
  final ConnectionInfo iptv;
  final ConnectionInfo trakt;
  final ConnectionInfo simkl;
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
    required this.reddit,
    required this.iptv,
    required this.trakt,
    required this.simkl,
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
  // [trakt,       simkl]
  // [mdblist]     (alone)
  late final FocusNode _torboxFocusNode;
  late final FocusNode _premiumizeFocusNode;
  late final FocusNode _allDebridFocusNode;
  late final FocusNode _pikpakFocusNode;
  late final FocusNode _webDavFocusNode;
  late final FocusNode _indexerManagersFocusNode;
  late final FocusNode _redditFocusNode;
  late final FocusNode _iptvFocusNode;
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
    _redditFocusNode = FocusNode(debugLabel: 'settings-reddit');
    _iptvFocusNode = FocusNode(debugLabel: 'settings-iptv');
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
    _redditFocusNode.dispose();
    _iptvFocusNode.dispose();
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
            // [Trakt]       [Simkl]
            // [MDBList]
            return Wrap(
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
                    downNeighbor: wide ? _pikpakFocusNode : _allDebridFocusNode,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: ConnectionCard(
                    info: widget.allDebrid,
                    focusNode: _allDebridFocusNode,
                    isLeftColumn: !wide,
                    leftNeighbor: wide ? _premiumizeFocusNode : null,
                    upNeighbor: wide ? _torboxFocusNode : _premiumizeFocusNode,
                    downNeighbor: wide ? _webDavFocusNode : _pikpakFocusNode,
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
                    upNeighbor: wide ? _allDebridFocusNode : _pikpakFocusNode,
                    downNeighbor: wide
                        ? _iptvFocusNode
                        : _indexerManagersFocusNode,
                  ),
                ),
                // Row 4: Indexer managers (left), IPTV (right).
                // The Reddit card that used to sit here is hidden — the
                // source is retired but widget.reddit/_redditFocusNode are
                // kept so the API and settings code stay untouched.
                SizedBox(
                  width: itemWidth,
                  child: ConnectionCard(
                    info: widget.indexerManagers,
                    focusNode: _indexerManagersFocusNode,
                    isLeftColumn: true,
                    rightNeighbor: wide ? _iptvFocusNode : null,
                    upNeighbor: wide ? _pikpakFocusNode : _webDavFocusNode,
                    downNeighbor: wide ? _traktFocusNode : _iptvFocusNode,
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
                    // Wide grid: Simkl (row 5 right) now sits directly below
                    // IPTV (row 4 right), not Trakt (row 5 left).
                    downNeighbor: wide ? _simklFocusNode : _traktFocusNode,
                  ),
                ),
                // Row 5: Trakt (left), Simkl (right)
                SizedBox(
                  width: itemWidth,
                  child: ConnectionCard(
                    info: widget.trakt,
                    focusNode: _traktFocusNode,
                    isLeftColumn: true,
                    rightNeighbor: wide ? _simklFocusNode : null,
                    upNeighbor: wide
                        ? _indexerManagersFocusNode
                        : _iptvFocusNode,
                    // Wide: MDBList sits alone in the left column of row 6,
                    // directly below Trakt. Narrow (single column): the next
                    // card down is Simkl, not MDBList. When MDBList is hidden
                    // (alpha), down goes nowhere in wide.
                    downNeighbor: wide
                        ? (widget.mdblist != null ? _mdblistFocusNode : null)
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
                    upNeighbor: wide ? _iptvFocusNode : _traktFocusNode,
                    // Down lands on the lone MDBList card, or nowhere when it's
                    // hidden (alpha).
                    downNeighbor:
                        widget.mdblist != null ? _mdblistFocusNode : null,
                  ),
                ),
                // Row 6: MDBList (left column, alone — no right partner).
                // Omitted entirely when MDBList is hidden for the alpha.
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
  bool _focused = false;
  bool _hovered = false;

  // Helper to focus and scroll into view
  void _focusAndScroll(FocusNode target) {
    target.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (target.context != null) {
        Scrollable.ensureVisible(
          target.context!,
          alignment: 0.3,
          duration: const Duration(milliseconds: 200),
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
    final info = widget.info;
    final String statusLower = info.status.toLowerCase();
    final bool active = info.connected && statusLower == 'active';
    // One color for both the dot and the status text so they can't disagree.
    final Color stateColor = info.connected
        ? (active ? kSettingsGreen : kSettingsRed)
        : kSettingsDim2;
    final bool lit = _focused || _hovered;

    return Focus(
      onKeyEvent: _onKeyEvent,
      // hasFocus includes the InkWell child node, so this lights up when the
      // card's InkWell receives DPAD focus.
      onFocusChange: (f) => setState(() => _focused = f),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // Plain Container (snap, no tween): animating a blurred BoxShadow
        // re-rasterizes per frame and janks weak TV GPUs (see
        // tv_sidebar_nav.dart for the same rule).
        child: Container(
          decoration: BoxDecoration(
            color: lit ? kSettingsPanel2 : kSettingsPanel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? kSettingsAccent : kSettingsLine,
              width: 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: kSettingsAccent.withValues(alpha: 0.28),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              focusNode: widget.focusNode,
              borderRadius: BorderRadius.circular(14),
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
                        color: Colors.white.withValues(alpha: 0.055),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: kSettingsLine),
                      ),
                      child: Text(
                        settingsInitialsFor(info.title),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: lit ? kSettingsAccent2 : kSettingsDim,
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
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            info.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: kSettingsDim,
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
                      color: kSettingsDim2,
                    ),
                  ],
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

  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) SettingsSectionLabel(title, color: accentColor),
        Container(
          decoration: BoxDecoration(
            color: kSettingsPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kSettingsLine, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i != 0)
                    Divider(height: 1, thickness: 1, color: kSettingsLine),
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
      focusNode: focusNode,
    );
  }

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool lit = _focused || _hovered;
    final Color iconColor = widget.destructive
        ? kSettingsRed
        : (lit ? kSettingsAccent2 : kSettingsDim);
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return Container(
      decoration: BoxDecoration(
        color: lit ? kSettingsPanel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? kSettingsAccent : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        onHover: (h) => setState(() => _hovered = h),
        onTap: () async {
          await widget.onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
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
                                  ? kSettingsRed
                                  : Colors.white,
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
                              color: kSettingsAccent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              widget.tag!,
                              style: const TextStyle(
                                color: kSettingsAccent2,
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
                      style: TextStyle(fontSize: 11.5, color: kSettingsDim),
                    ),
                  ],
                ),
              ),
              widget.trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: kSettingsDim2,
                  ),
            ],
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
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool lit = _focused || _hovered;
    // Snap, don't tween — per-keypress decoration lerps add cost on TV.
    return Container(
      decoration: BoxDecoration(
        color: lit ? kSettingsPanel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? kSettingsAccent : Colors.transparent,
          width: 1,
        ),
      ),
      child: InkWell(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setState(() => _focused = f),
        onHover: (h) => setState(() => _hovered = h),
        onTap: () => widget.onChanged(!widget.value),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Icon(
                  widget.icon,
                  color: lit ? kSettingsAccent2 : kSettingsDim,
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
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      maxLines: widget.subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: kSettingsDim),
                    ),
                  ],
                ),
              ),
              // The row's InkWell is the single DPAD stop; a focusable Switch
              // would make every toggle cost two presses on TV.
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
    );
  }
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

  const SettingsSelectDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final SettingsSelectOption? selected = options
        .cast<SettingsSelectOption?>()
        .firstWhere((o) => o!.value == value, orElse: () => null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          // A stale stored value (e.g. removed option) renders as an empty
          // field instead of tripping DropdownButton's value assert.
          value: selected?.value,
          isExpanded: true,
          // Variable item heights so subtitles fit in the open menu.
          itemHeight: null,
          dropdownColor: kSettingsPanel2,
          borderRadius: BorderRadius.circular(14),
          // No focusColor: with an InputDecoration the SDK swaps the fill
          // color for it on focus, which would blank the panel fill. Focus
          // is carried by the themed focusedBorder instead.
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: kSettingsDim),
          decoration: const InputDecoration(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
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
                              ? kSettingsAccent2
                              : Colors.white,
                        ),
                      ),
                      if (o.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          o.subtitle!,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: kSettingsDim,
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
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: kSettingsDim,
              ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: kSettingsDim, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kSettingsLine),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kSettingsDim,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Shimmer(width: 120, height: 12),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: kSettingsPanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kSettingsLine),
          ),
          child: Column(
            children: [
              const _SkeletonTile(),
              Divider(height: 1, color: kSettingsLine),
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
