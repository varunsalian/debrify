import '../widgets/detail/theme/detail_theme.dart';
import '../widgets/detail/theme/detail_themes.dart';
import 'theme_overrides.dart';
import 'theme_palette.dart';

/// Resolves a theme id plus the user's overrides into the `DetailTheme` core
/// everything else is derived from.
///
/// **Shared, not private to the controller.** The detail layouts fetch their
/// core straight from the registry rather than from `AppThemeController`, so a
/// core patched only inside the controller would leave every alternate detail
/// page showing the unedited theme. One resolver, used by both, is the only way
/// those two agree.
///
/// **Memoized on (id, overrides).** Resolution runs on every theme recompute
/// and on every detail page build; the work is a dozen colour derivations, and
/// repeating it per build on a Mi-Box-class CPU is exactly the kind of cost the
/// controller's own memoization exists to avoid.
abstract final class ThemeCoreResolver {
  static String? _key;
  static DetailTheme? _cached;

  /// The core for [id], with [overrides] applied.
  ///
  /// Returns the registry's own theme untouched when there is nothing to apply
  /// — the fast path, and the reason an unedited install resolves down exactly
  /// the code it always did.
  static DetailTheme resolve(String id, ThemeOverrides overrides) {
    final base = DetailThemes.byId(id);
    if (!overrides.touchesCore) return base;

    final key = '$id|${overrides.encode()}';
    if (key == _key && _cached != null) return _cached!;

    final resolved = base.withTokens(
      // A swatch id nobody recognises resolves to null, which `withTokens`
      // reads as "leave this alone" — so a dropped swatch shows the theme's own
      // colour rather than something arbitrary.
      accent: ThemePalette.colorOf(overrides.accent),
      focus: ThemePalette.colorOf(overrides.focusColor),
      state: ThemePalette.colorOf(overrides.state),
      callout: ThemePalette.colorOf(overrides.callout),
      ground: ThemePalette.colorOf(overrides.ground),
      pane: ThemePalette.colorOf(overrides.pane),
      panel: ThemePalette.colorOf(overrides.panel),
      tx: ThemePalette.colorOf(overrides.ink),
      radius: overrides.resolvedRadius,
      pillRadius: overrides.resolvedPillRadius,
      displayFont: overrides.resolvedDisplayFont,
      bodyFont: overrides.resolvedBodyFont,
      grain: overrides.resolvedGrain,
      washOpacity: overrides.resolvedReactiveRoom,
      useArtworkAccent: overrides.resolvedArtworkAccent,
      separation: overrides.resolvedSeparation,
    );

    _key = key;
    _cached = resolved;
    return resolved;
  }

  /// Drops the memo. Only tests need this; production changes the key instead.
  static void debugReset() {
    _key = null;
    _cached = null;
  }
}
