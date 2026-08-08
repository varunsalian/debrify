import 'package:flutter/material.dart';

import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/detail/theme/detail_themes.dart';

/// App-wide theme: the details-page token core plus the per-surface role
/// tokens the chrome needs.
///
/// Two kinds of instance exist and only two:
///
/// * **`AppThemes.legacy`** — the compatibility profile. Every subprofile pins
///   the exact literal it replaces (`HomeTheme.focusGold`, `kSeeAllPanel`,
///   `kSettingsDim`, `CloudTheme.amber`, …), so a surface reading tokens under
///   `legacy` renders byte-for-byte what it rendered reading the constants.
///   Pinned by `test/theme/legacy_pins_test.dart` — if a constant and its pin
///   drift apart, that test fails, not a user's screen.
/// * **`AppTheme.fromDetail(core)`** — a real theme. Subprofiles are DERIVED
///   from the 20-theme detail core by the rules below. These derivations are
///   Foundation defaults: sweeps may refine them, but only by editing this
///   file (the no-agent-adds-a-token rule).
///
/// Naming: roles, never screens. `statusWarning` and `categoryFolder` are both
/// amber under legacy Cloud but are separate tokens on purpose — a theme must
/// be able to change one without misclassifying the other.
@immutable
class AppTheme {
  final String id;
  final String label;
  final bool isLegacy;

  /// The token core (grounds, text, meaning, shape, type). For real themes
  /// this is the selected [DetailTheme]; for legacy it is Signal, and the
  /// details page keeps resolving its OWN `detail_theme` pref instead.
  final DetailTheme core;

  final HomeTokens home;
  final SeeAllTokens seeAll;
  final SettingsTokens settings;
  final CloudTokens cloud;
  final ShellTokens shell;

  /// Light chrome ⇔ the ground reads light. One stated threshold, everywhere:
  /// `ground.computeLuminance() > 0.5`. Broadsheet (≈0.86) and Concrete
  /// (≈0.57) land light; every other shipped theme lands dark.
  final Brightness brightness;

  const AppTheme._({
    required this.id,
    required this.label,
    required this.isLegacy,
    required this.core,
    required this.home,
    required this.seeAll,
    required this.settings,
    required this.cloud,
    required this.shell,
    required this.brightness,
  });

  bool get isLight => brightness == Brightness.light;

  /// Scales a token's OWN alpha — same contract as [DetailTheme.fade].
  Color fade(Color c, double factor) =>
      c.withValues(alpha: (c.a * factor).clamp(0.0, 1.0));

  /// Derive a real app theme from a detail core.
  factory AppTheme.fromDetail(DetailTheme core) {
    final ground = core.ground;
    final light = ground.computeLuminance() > 0.5;
    final tx = core.tx;

    Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
    // Opaque elevated surfaces, stepped toward the text colour — the themed
    // equivalent of the legacy #17132E / #1E1840 panel pair.
    final panel = mix(ground, tx, 0.06);
    final panel2 = mix(ground, tx, 0.10);
    // The hairline flattened onto the ground, so it stays a LINE colour even
    // where it is drawn without the ground behind it.
    final line = Color.alphaBlend(core.hair, ground);

    // Status/category trios are semantic, not theme fields: green means good
    // on every theme. Only their weight changes — the dark-ground trio glares
    // on paper, so light grounds get deepened variants (WCAG-checked in the
    // contrast cross-product test).
    final success = light ? const Color(0xFF1B7F4D) : const Color(0xFF10B981);
    final warning = light ? const Color(0xFFB45309) : const Color(0xFFF59E0B);
    final error = light ? const Color(0xFFB3261E) : const Color(0xFFEF4444);
    final catVideo = light ? const Color(0xFF1D4ED8) : const Color(0xFF60A5FA);
    final catSeason = light ? const Color(0xFF6D28D9) : const Color(0xFFA78BFA);

    final wash = RadialGradient(
      center: const Alignment(0, -0.75),
      radius: 1.35,
      colors: [
        mix(core.pane, core.accent, 0.10),
        mix(core.pane, ground, 0.55),
        ground,
        ground,
      ],
      stops: const [0.0, 0.38, 0.68, 1.0],
    );

    return AppTheme._(
      id: core.id,
      label: core.label,
      isLegacy: false,
      core: core,
      brightness: light ? Brightness.light : Brightness.dark,
      home: HomeTokens(
        bg: ground,
        wash: wash,
        chromeAccent: core.accent,
        focus: core.focus,
        focusDeep: core.state,
        highlight: core.callout,
        danger: error,
      ),
      seeAll: SeeAllTokens(
        bg: ground,
        accent: core.accent,
        accent2: mix(core.accent, tx, 0.30),
        panel: panel,
        panel2: panel2,
        accentBorder: core.accent.withValues(alpha: 0.38),
        line: line,
      ),
      settings: SettingsTokens(
        bg: ground,
        accent: core.accent,
        accent2: mix(core.accent, tx, 0.30),
        panel: panel,
        panel2: panel2,
        success: success,
        danger: error,
        warning: warning,
        line: line,
        dim: tx.withValues(alpha: 0.46),
        dim2: tx.withValues(alpha: 0.28),
      ),
      cloud: CloudTokens(
        bg: ground,
        accent: core.accent,
        menuSurface: mix(ground, tx, 0.08),
        wash: wash,
        statusSuccess: success,
        statusWarning: warning,
        statusError: error,
        destructive: error,
        categoryVideo: catVideo,
        categoryFolder: warning,
        categorySeason: catSeason,
      ),
      shell: ShellTokens(
        ink: ground,
        sidebarScrim: Colors.black.withValues(alpha: 0.54),
        railVeil: ground.withValues(alpha: 0.92),
      ),
    );
  }
}

/// Home / Search / Discover board chrome. Only the LIVE `HomeTheme` colour
/// symbols get roles — the audit found `accent`, `cardBg` and the progress
/// gradients have zero live consumers, and dead symbols get no tokens.
@immutable
class HomeTokens {
  /// `HomeTheme.bg` — the board's page ink.
  final Color bg;

  /// `HomeTheme.pageBackground` — the dim indigo bloom behind the board.
  final Gradient wash;

  /// `HomeTheme.chromeAccent` — active chrome (search pill, mode toggle).
  final Color chromeAccent;

  /// `HomeTheme.focusGold` — the content DPAD cursor.
  final Color focus;

  /// `HomeTheme.focusGoldDeep` — the cursor's soft bloom partner.
  final Color focusDeep;

  /// `HomeTheme.highlight` — live / now-playing indicators only.
  final Color highlight;

  /// `HomeTheme.danger` — destructive actions.
  final Color danger;

  const HomeTokens({
    required this.bg,
    required this.wash,
    required this.chromeAccent,
    required this.focus,
    required this.focusDeep,
    required this.highlight,
    required this.danger,
  });
}

/// See-All / Discover / Addons chrome (the `kSeeAll*` vocabulary).
@immutable
class SeeAllTokens {
  final Color bg;
  final Color accent;
  final Color accent2;
  final Color panel;
  final Color panel2;
  final Color accentBorder;
  final Color line;

  const SeeAllTokens({
    required this.bg,
    required this.accent,
    required this.accent2,
    required this.panel,
    required this.panel2,
    required this.accentBorder,
    required this.line,
  });
}

/// Settings chrome (the `kSettings*` vocabulary).
@immutable
class SettingsTokens {
  final Color bg;
  final Color accent;
  final Color accent2;
  final Color panel;
  final Color panel2;
  final Color success;
  final Color danger;
  final Color warning;
  final Color line;
  final Color dim;
  final Color dim2;

  const SettingsTokens({
    required this.bg,
    required this.accent,
    required this.accent2,
    required this.panel,
    required this.panel2,
    required this.success,
    required this.danger,
    required this.warning,
    required this.line,
    required this.dim,
    required this.dim2,
  });
}

/// Cloud chrome (the `CloudTheme` vocabulary), with the category/status split
/// the plan mandates: legacy amber is BOTH the folder category and the warning
/// badge, and folding those into one `status*` set would misclassify folders.
@immutable
class CloudTokens {
  final Color bg;
  final Color accent;
  final Color menuSurface;
  final Gradient wash;
  final Color statusSuccess;
  final Color statusWarning;
  final Color statusError;
  final Color destructive;
  final Color categoryVideo;
  final Color categoryFolder;
  final Color categorySeason;

  const CloudTokens({
    required this.bg,
    required this.accent,
    required this.menuSurface,
    required this.wash,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.destructive,
    required this.categoryVideo,
    required this.categoryFolder,
    required this.categorySeason,
  });
}

/// The app shell: scaffold ink and the TV rail's two scrims.
@immutable
class ShellTokens {
  /// The opaque page ink behind every non-TV page (`HomeTheme.bg` today).
  final Color ink;

  /// Dim over content while the TV sidebar overlay is open (`0x8A05060E`).
  final Color sidebarScrim;

  /// The lights-off veil over the collapsed rail strip (`0xEB0D0B1A`).
  final Color railVeil;

  const ShellTokens({
    required this.ink,
    required this.sidebarScrim,
    required this.railVeil,
  });
}

/// The registry.
abstract final class AppThemes {
  /// The stored sentinel meaning "render today's app exactly".
  static const String legacyId = 'legacy';

  /// The compatibility profile. Every value below is a PIN of a literal that
  /// exists elsewhere in the tree; `legacy_pins_test.dart` asserts agreement
  /// with the real constants so the two can never drift silently.
  ///
  /// `final`, not `const`: the handful of `withValues(alpha:)` pins
  /// (`kSeeAllAccentBorder`, `kSettingsDim`, …) cannot be const, and splitting
  /// the profile across const/non-const halves for their sake would not be
  /// worth the reading cost.
  static final AppTheme legacy = AppTheme._(
    id: legacyId,
    label: 'Debrify Classic',
    isLegacy: true,
    core: DetailThemes.signal,
    brightness: Brightness.dark,
    home: HomeTokens(
      bg: const Color(0xFF0D0B1A), // HomeTheme.bg
      wash: _legacyWash, // HomeTheme.pageBackground
      chromeAccent: const Color(0xFF7B5CFF), // HomeTheme.chromeAccent
      focus: const Color(0xFFFBBF24), // HomeTheme.focusGold
      focusDeep: const Color(0xFFF59E0B), // HomeTheme.focusGoldDeep
      highlight: const Color(0xFFF59E0B), // HomeTheme.highlight
      danger: const Color(0xFFEF4444), // HomeTheme.danger
    ),
    seeAll: SeeAllTokens(
      bg: const Color(0xFF0D0B1A), // kSeeAllBg
      accent: const Color(0xFF7B5CFF), // kSeeAllAccent
      accent2: const Color(0xFF9B7BFF), // kSeeAllAccent2
      panel: const Color(0xFF17132E), // kSeeAllPanel
      panel2: const Color(0xFF1E1840), // kSeeAllPanel2
      accentBorder: // kSeeAllAccentBorder
          const Color(0xFF7B5CFF).withValues(alpha: 0.38),
      line: // kSeeAllLine
          const Color(0xFFB4A0FF).withValues(alpha: 0.12),
    ),
    settings: SettingsTokens(
      bg: const Color(0xFF0D0B1A), // kSettingsBg
      accent: const Color(0xFF7B5CFF), // kSettingsAccent
      accent2: const Color(0xFF9B7BFF), // kSettingsAccent2
      panel: const Color(0xFF17132E), // kSettingsPanel
      panel2: const Color(0xFF1E1840), // kSettingsPanel2
      success: const Color(0xFF39D98A), // kSettingsGreen
      danger: const Color(0xFFE5484D), // kSettingsRed
      warning: const Color(0xFFF5A623), // kSettingsAmber
      line: // kSettingsLine
          const Color(0xFFB4A0FF).withValues(alpha: 0.12),
      dim: Colors.white.withValues(alpha: 0.46), // kSettingsDim
      dim2: Colors.white.withValues(alpha: 0.28), // kSettingsDim2
    ),
    cloud: CloudTokens(
      bg: const Color(0xFF0D0B1A), // CloudTheme.bg
      accent: const Color(0xFF7B5CFF), // CloudTheme.accent
      menuSurface: const Color(0xFF1E1B2C), // CloudTheme.menuSurface
      wash: _legacyWash, // CloudTheme.pageGradient (same stops)
      statusSuccess: const Color(0xFF10B981), // CloudTheme.green
      statusWarning: const Color(0xFFF59E0B), // CloudTheme.amber (warning use)
      statusError: const Color(0xFFEF4444), // CloudTheme.red
      destructive: const Color(0xFFEF4444), // CloudTheme.red
      categoryVideo: const Color(0xFF60A5FA), // CloudTheme.blue
      categoryFolder: const Color(0xFFF59E0B), // CloudTheme.amber (folder use)
      categorySeason: const Color(0xFFA78BFA), // CloudTheme.purple
    ),
    shell: const ShellTokens(
      ink: Color(0xFF0D0B1A), // main.dart Scaffold backgroundColor
      sidebarScrim: Color(0x8A05060E), // main.dart TV sidebar scrim
      railVeil: Color(0xEB0D0B1A), // main.dart lights-off rail veil
    ),
  );

  /// `HomeTheme.pageBackground` / `CloudTheme.pageGradient` — one gradient,
  /// two legacy constants with identical stops.
  static const RadialGradient _legacyWash = RadialGradient(
    center: Alignment(0, -0.75),
    radius: 1.35,
    colors: [
      Color(0xFF241E44),
      Color(0xFF161327),
      Color(0xFF0F0D1D),
      Color(0xFF0D0B1A),
    ],
    stops: [0.0, 0.38, 0.68, 1.0],
  );

  /// Resolve a stored id. Unknown or removed ids fall back to LEGACY, never to
  /// a random theme — a downgraded build must render the app it shipped.
  static AppTheme byId(String id) {
    if (id == legacyId) return legacy;
    for (final core in DetailThemes.all) {
      if (core.id == id) return AppTheme.fromDetail(core);
    }
    return legacy;
  }
}
