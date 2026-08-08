import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/text_brightness.dart';
import '../utils/platform_util.dart';
import '../widgets/detail/theme/detail_theme.dart';
import 'app_theme.dart';

/// TV-aware page transition: on Android TV every push/pop animates a
/// full-screen layer, and the default Material zoom transition (scale + fade +
/// snapshotting) is visibly janky on weak TV GPUs — it's a big part of why the
/// app doesn't feel native there. TV gets a plain fast fade instead: the
/// incoming page fades in over the first 40% of the route animation (~120ms of
/// the standard 300ms), which reads as an instant, native-style switch and
/// costs one opacity layer. Phones keep the stock zoom transition untouched.
///
/// The TV check reads [PlatformUtil.isTelevision] per transition build —
/// warmed in main() before runApp — so the ThemeData stays const/synchronous.
///
/// (Moved verbatim from `main.dart` when the ThemeData construction moved into
/// this adapter; every built theme shares it.)
class TvAwarePageTransitionsBuilder extends PageTransitionsBuilder {
  const TvAwarePageTransitionsBuilder();

  static const PageTransitionsBuilder _phoneDefault =
      ZoomPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (PlatformUtil.isTelevision) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
        ),
        child: child,
      );
    }
    return _phoneDefault.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Builds `ThemeData` and system-bar styles from an [AppTheme].
///
/// Two entirely separate paths, on purpose:
///
/// * [legacy] returns the app's shipped root theme BYTE-FOR-BYTE — the
///   `ThemeData` construction below was moved verbatim out of `main.dart`,
///   text-brightness post-pass included. Under the `legacy` app theme the
///   root `MaterialApp` renders from exactly the same inputs it always has.
/// * [themed] builds a real theme's `ThemeData` from a RAW construction —
///   never by `copyWith` over the legacy one, which has already been through
///   the text-brightness pass and would double-apply the preset.
abstract final class AppThemeAdapter {
  /// Shared by both paths — TV gets the fast fade, phones the stock zoom.
  static const PageTransitionsTheme pageTransitions = PageTransitionsTheme(
    builders: {TargetPlatform.android: TvAwarePageTransitionsBuilder()},
  );

  /// TEST-ONLY: skip the GoogleFonts wrapper and use the raw type skeleton.
  /// Widget tests have no Inter asset, so every ThemeData build otherwise
  /// logs a font-load "Error:" block that buries real failures — and the
  /// tests deliberately pin colour/layout, not typography. Never set in
  /// production code; the legacy path's verbatim claim holds with this false.
  @visibleForTesting
  static bool debugUseTestTypography = false;

  static TextTheme get _textTheme => debugUseTestTypography
      ? _textSkeleton
      : GoogleFonts.interTextTheme(_textSkeleton);

  // ───────────────────────────── legacy path ─────────────────────────────

  /// Today's root theme, preset applied — what `MaterialApp.theme` has always
  /// received.
  static ThemeData legacy(TextBrightness preset) =>
      _applyTextBrightness(_legacyBase(), preset);

  /// Today's imperative system-bar call, verbatim (`_initOrientation`):
  /// transparent navigation bar, light icons, nothing else touched.
  static const SystemUiOverlayStyle legacySystemBars = SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  /// The shipped root ThemeData. Moved UNCHANGED from `main.dart` — if this
  /// construction drifts from what shipped, `legacy` stops meaning anything,
  /// so treat every value as pinned.
  static ThemeData _legacyBase() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    // TV: fast fade instead of the Material zoom push/pop (see
    // TvAwarePageTransitionsBuilder). Phones/desktop keep their defaults.
    pageTransitionsTheme: pageTransitions,
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
    textTheme: _textTheme,
    cardTheme: CardThemeData(
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: const Color(0xFF141824),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
      elevation: 8,
    ),
  );

  /// Tones the theme's text down per the Appearance → Text Brightness preset.
  ///
  /// A POST-transform of the finished theme rather than different construction
  /// inputs, so [TextBrightness.bright] returns [base] untouched — the default
  /// look cannot regress by construction. For soft/dim it retargets only what
  /// text reads: `onSurface` (+ `onSurfaceVariant` where the preset says so),
  /// every `textTheme` color (the theme has merged typography defaults in by
  /// now, so `apply` covers all fifteen styles), the app-bar title and the
  /// snackbar body. Icons, buttons, on-accent text and surfaces are none of
  /// this pass's business.
  ///
  /// (Moved verbatim from `main.dart`. LEGACY ONLY: its fixed light greys are
  /// nearly invisible on a light ground, which is why the themed path resolves
  /// the preset through [resolveCoreText] instead.)
  static ThemeData _applyTextBrightness(ThemeData base, TextBrightness preset) {
    final Color? text = preset.primary;
    if (text == null) return base;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        onSurface: text,
        onSurfaceVariant: preset.secondary,
      ),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(color: text),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        contentTextStyle: base.snackBarTheme.contentTextStyle?.copyWith(
          color: text,
        ),
      ),
    );
  }

  // ───────────────────────────── themed path ─────────────────────────────

  /// The Text Brightness preset resolved against a REAL theme's core:
  /// PROPORTIONAL toning toward the theme's own ground, not the legacy pass's
  /// fixed light greys (invisible on Broadsheet's paper).
  ///
  /// Factors are calibrated so a white-on-black theme reproduces the legacy
  /// greys within rounding: soft ≈ 11% toward ground (#E3… vs legacy #E4E4E7),
  /// dim ≈ 23% (#C4… vs legacy #C4C7CE). `tx2`/`tx3` stay untouched — they are
  /// already sub-70% tones, and the preset's complaint has only ever been
  /// glaring PRIMARY text. Enforced across every (theme × preset) pair by the
  /// contrast cross-product test.
  static DetailTheme resolveCoreText(DetailTheme core, TextBrightness preset) {
    final double f = switch (preset) {
      TextBrightness.bright => 0,
      TextBrightness.soft => 0.11,
      TextBrightness.dim => 0.23,
    };
    if (f == 0) return core;
    final ground = core.ground.withValues(alpha: 1);
    return core.withText(tx: Color.lerp(core.tx, ground, f)!);
  }

  /// A real theme's `ThemeData`, built from a RAW construction.
  ///
  /// [theme]'s core must already be preset-resolved (the controller runs
  /// [resolveCoreText] before deriving the [AppTheme]); [preset] is still
  /// passed for the one thing proportional toning can't express — dim's
  /// extra secondary-text step.
  ///
  /// Colour mapping only: component GEOMETRY (radii, paddings, elevations)
  /// deliberately mirrors the legacy construction so switching themes never
  /// reflows a layout — the detail core's radius engine stays a details-page
  /// affair until a later phase decides otherwise.
  static ThemeData themed(AppTheme theme, TextBrightness preset) {
    final core = theme.core;
    final ground = core.ground.withValues(alpha: 1);
    final tx = core.tx;

    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    Color step(double t) => mix(ground, tx, t);
    // Text/icon colour ON a filled swatch: the swatch's own opposite.
    Color onFill(Color fill) => fill.computeLuminance() > 0.5
        ? const Color(0xFF111114)
        : Colors.white;

    final line = Color.alphaBlend(core.hair, ground);
    // Secondary text, flattened opaque so Material controls can dim/blend it.
    Color variant = Color.alphaBlend(core.tx2, ground);
    if (preset == TextBrightness.dim) {
      // Dim's second step: keep titles reading brighter than subtitles once
      // primary text has been toned 23% toward the ground.
      variant = mix(variant, ground, 0.15);
    }

    final error = theme.cloud.statusError;
    final surface = core.pane.withValues(alpha: 1);

    final colorScheme = ColorScheme(
      brightness: theme.brightness,
      primary: core.accent,
      onPrimary: onFill(core.accent),
      primaryContainer: mix(core.accent, ground, 0.60),
      onPrimaryContainer: tx,
      secondary: core.state,
      onSecondary: onFill(core.state),
      secondaryContainer: mix(core.state, ground, 0.60),
      onSecondaryContainer: tx,
      tertiary: core.callout,
      onTertiary: core.calloutText,
      tertiaryContainer: mix(core.callout, ground, 0.60),
      onTertiaryContainer: tx,
      surface: surface,
      onSurface: tx,
      onSurfaceVariant: variant,
      surfaceContainerHighest: step(0.10),
      surfaceContainerHigh: step(0.14),
      surfaceContainer: step(0.20),
      surfaceContainerLow: step(0.26),
      surfaceContainerLowest: step(0.55),
      error: error,
      onError: onFill(error),
      errorContainer: mix(error, ground, 0.60),
      onErrorContainer: tx,
      outline: mix(line, tx, 0.25),
      outlineVariant: line,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: mix(tx, ground, 0.05),
      onInverseSurface: ground,
      inversePrimary: mix(core.accent, ground, 0.30),
      surfaceTint: core.accent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: theme.brightness,
      pageTransitionsTheme: pageTransitions,
      colorScheme: colorScheme,
      // Same Inter skeleton as legacy; colours derive from onSurface.
      textTheme: _textTheme,
      scaffoldBackgroundColor: ground,
      cardTheme: CardThemeData(
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: step(0.10),
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
          side: BorderSide(color: step(0.20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: step(0.14),
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
          borderSide: BorderSide(color: core.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: tx,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: tx,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: step(0.08),
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: step(0.10)),
      dividerTheme: DividerThemeData(color: line),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(tx.withValues(alpha: 0.30)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: core.accent,
        selectionColor: core.accent.withValues(alpha: 0.35),
        selectionHandleColor: core.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: step(0.10),
        contentTextStyle: TextStyle(color: tx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
      ),
    );
  }

  /// System bars for a real theme: transparent bars, icon brightness from the
  /// theme's ground. (`Brightness.dark` ICONS on a light ground — the
  /// SystemUiOverlayStyle naming is icon-colour-inverse.)
  static SystemUiOverlayStyle themedSystemBars(AppTheme theme) =>
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            theme.isLight ? Brightness.dark : Brightness.light,
        statusBarBrightness: theme.brightness, // iOS reads this one.
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            theme.isLight ? Brightness.dark : Brightness.light,
      );

  /// The shipped type scale — shared verbatim by both paths.
  static const TextTheme _textSkeleton = TextTheme(
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
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
  );
}
