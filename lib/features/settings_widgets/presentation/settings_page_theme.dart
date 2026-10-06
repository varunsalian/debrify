import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

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
