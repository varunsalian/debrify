import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_theme_controller.dart';

/// Provides the active [AppTheme] to the tree.
///
/// Installed ONCE, above the root Navigator (in `MaterialApp.builder`), so
/// every route, dialog, sheet and root overlay inherits it without capture.
/// [LegacyThemeBoundary]-style freezes shadow it lower down for excluded
/// surfaces.
///
/// An [InheritedTheme] so `InheritedTheme.capture` carries it across the
/// mechanisms that skip ambient inheritance (`showGeneralDialog`,
/// `RawDialogRoute`, bare `OverlayEntry`) — a plain InheritedWidget is
/// silently dropped by capture, which is exactly the bug this layer must not
/// have.
class AppThemeScope extends InheritedTheme {
  final AppTheme theme;

  const AppThemeScope({super.key, required this.theme, required super.child});

  @override
  Widget wrap(BuildContext context, Widget child) =>
      AppThemeScope(theme: theme, child: child);

  @override
  bool updateShouldNotify(AppThemeScope oldWidget) =>
      !identical(oldWidget.theme, theme);

  /// The active app theme.
  ///
  /// Falls back to the controller's current theme (never null) so widgets
  /// rendered outside the scope — tests pumping a bare widget, tooling —
  /// degrade to the selected theme rather than throwing. Production trees are
  /// always inside the root scope.
  static AppTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.theme ??
      AppThemeController.instance.theme;

  static AppTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppThemeScope>()?.theme;
}
