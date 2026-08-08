import 'package:flutter/services.dart';

import 'app_surfaces.dart';
import 'app_theme_adapter.dart';
import 'app_theme_controller.dart';

/// The one owner of system-bar styling at shell/route level.
///
/// Reads the active-surface signal — current tab, top route, bootstrap
/// overlay — plus the theme controller, and applies imperatively:
///
/// * legacy theme, or any FROZEN active surface → today's style verbatim
///   (transparent nav bar, light icons; nothing else touched);
/// * a real theme on a THEMED surface → transparent bars with icon brightness
///   from the theme's ground.
///
/// Replaces the one-time imperative call as the ongoing authority (the
/// `_initOrientation` call still runs first as the pre-`runApp` default; this
/// owner re-applies on every surface or theme change from then on).
///
/// Deliberately NOT an `AnnotatedRegion`: a region inside a destination
/// boundary sits within `SafeArea` and never covers the bar coordinates, so a
/// top-level region always wins — and excluded screens (the player above all)
/// call `SystemChrome` themselves. Known co-authors remain: any route with an
/// `AppBar` asserts its own overlay style derived from the SAME ThemeData
/// this owner derives from, so the two never disagree about a themed page;
/// the owner simply re-establishes the style when no AppBar is asserting.
abstract final class SystemBarsOwner {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;
    AppSurfaceState.instance.addListener(_apply);
    AppThemeController.instance.addListener(_apply);
    _apply();
  }

  static void _apply() {
    final controller = AppThemeController.instance;
    final frozen = controller.isLegacy ||
        AppSurfaceState.instance.active == SurfaceKind.frozen;
    SystemChrome.setSystemUIOverlayStyle(
      frozen
          ? AppThemeAdapter.legacySystemBars
          : AppThemeAdapter.themedSystemBars(controller.theme),
    );
  }
}
