import 'package:flutter/material.dart';

import 'app_theme_controller.dart';
import 'app_theme_scope.dart';

/// Freezes a subtree on today's look, whatever the app theme says.
///
/// Installed at every EXCLUDED entry point — frozen tab bodies (via the tab
/// factory), pushed excluded routes (via `FrozenLegacyPageRoute`), and the
/// bootstrap overlays (splash, onboarding). Inside it:
///
/// * `Theme.of` resolves to the legacy root `ThemeData` at the current
///   text-brightness preset — exactly what these screens have always seen.
/// * `AppThemeScope.of` resolves to the legacy token profile, shadowing the
///   live scope above the Navigator. Shadowing BOTH is the point: a frozen
///   subtree that still sees live tokens is worse than one that sees neither.
///
/// Both `Theme` and `AppThemeScope` are InheritedThemes, so dialogs and sheets
/// launched from a frozen context CAPTURE the freeze automatically — overlay
/// mechanisms that skip capture (`showGeneralDialog`, bare `OverlayEntry`) are
/// routed through `captureAppThemes` instead (see `overlay_theme.dart`).
///
/// [withMessenger] installs a boundary-local [ScaffoldMessenger] — but ONLY
/// while a real app theme is active. This is the snackbar decision the plan
/// required Foundation to make: the root messenger presents on the root-most
/// Scaffold — OUTSIDE any boundary — so under a real theme a snackbar
/// requested by frozen IPTV code would render app-themed; the local messenger
/// makes `ScaffoldMessenger.of(context)` inside the subtree resolve here and
/// present on the surface's own (frozen) Scaffold instead. Under `legacy` the
/// messenger is NOT installed, deliberately: root-messenger snackbars survive
/// tab switches and route pops, a local queue's die with their subtree, and
/// that lifetime difference must not ship to users who never chose a theme.
/// The trade only exists under a real theme, where a wrong-coloured snackbar
/// is the worse of the two evils.
///
/// The insert/remove on legacy↔real transition changes the subtree's depth,
/// which remounts the boundary's child. Acceptable: theme changes happen on
/// the App Theme settings page, at which point no frozen tab body is mounted
/// (the shell builds only the selected tab) and no frozen route can be open
/// above Settings.
///
/// On for frozen tab bodies and excluded routes, all of which own a Scaffold;
/// off for the bootstrap splash, which is not a snackbar surface. The global
/// `scaffoldMessengerKey` used by services still targets the root messenger —
/// service-level messages are app-level, not surface-level, and keep the app
/// theme deliberately.
class LegacyThemeBoundary extends StatelessWidget {
  final Widget child;
  final bool withMessenger;

  const LegacyThemeBoundary({
    super.key,
    required this.child,
    this.withMessenger = false,
  });

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder, not a plain read: a frozen ROUTE's subtree does not
    // necessarily rebuild when the root MaterialApp re-themes, so the freeze
    // must follow the text-brightness preset on its own subscription.
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final controller = AppThemeController.instance;
        Widget frozen = AppThemeScope(
          theme: controller.legacyTheme,
          child: child,
        );
        frozen = Theme(data: controller.legacyThemeData, child: frozen);
        if (withMessenger && !controller.isLegacy) {
          frozen = ScaffoldMessenger(child: frozen);
        }
        return frozen;
      },
    );
  }
}
