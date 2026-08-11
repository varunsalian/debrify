import 'package:flutter/material.dart';

import 'app_theme_controller.dart';
import 'app_theme_scope.dart';

/// Theme carriage for the overlay mechanisms that SKIP ambient inheritance —
/// `showGeneralDialog`, `RawDialogRoute` and bare `OverlayEntry`. (`showDialog`
/// and `showModalBottomSheet` capture `InheritedTheme`s on their own and need
/// neither helper; included surfaces launching ROOT overlays inherit the live
/// root scope and also need neither.)
///
/// Two flavours, and they are deliberately not the same helper:
///
/// * [captureAppThemes] — the SNAPSHOT wrapper. Captures every InheritedTheme
///   (`Theme`, `AppThemeScope`, `DetailThemeScope`, …) between the LAUNCHING
///   context and the root navigator, so the overlay renders what its launcher
///   saw: frozen if launched inside a `LegacyThemeBoundary`, live-as-of-launch
///   otherwise. Right for transient overlays (loading masks, the TV keyboard).
/// * [AppThemeOverlayLive] — the LIVE wrapper, for long-lived overlays that
///   must restyle while open. It re-reads the controller on every change, so
///   a captured snapshot never goes stale. The details screen's local-theme
///   modals are its intended consumer (step 5 of the rollout).
CapturedThemes captureAppThemes(BuildContext from) => InheritedTheme.capture(
  from: from,
  to: Navigator.of(from, rootNavigator: true).context,
);

/// Wraps overlay content in the CURRENT app theme, re-resolved on every
/// controller change. See the library doc above for when to prefer this over
/// a capture.
class AppThemeOverlayLive extends StatelessWidget {
  final Widget child;

  const AppThemeOverlayLive({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final controller = AppThemeController.instance;
        return Theme(
          data: controller.themeData,
          child: AppThemeScope(theme: controller.theme, child: child),
        );
      },
    );
  }
}
