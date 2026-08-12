import 'package:flutter/material.dart';

import '../../services/text_brightness.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_adapter.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/premium_looks.dart';
import '../../theme/theme_core_resolver.dart';
import '../../theme/theme_overrides.dart';

class OnboardingThemePair {
  const OnboardingThemePair(this.app, this.material);

  final AppTheme app;
  final ThemeData material;
}

abstract final class OnboardingTheme {
  static OnboardingThemePair? _bright;
  static OnboardingThemePair? _soft;
  static OnboardingThemePair? _dim;

  static OnboardingThemePair resolve() {
    final preset = TextBrightnessController.current;
    final cached = switch (preset) {
      TextBrightness.bright => _bright,
      TextBrightness.soft => _soft,
      TextBrightness.dim => _dim,
    };
    if (cached != null) return cached;

    final core = AppThemeAdapter.resolveCoreText(
      ThemeCoreResolver.resolve('spotlight', ThemeOverrides.none),
      preset,
    );
    final app = PremiumLooks.spotlight.buildWith(core);
    final pair = OnboardingThemePair(app, AppThemeAdapter.themed(app, preset));
    switch (preset) {
      case TextBrightness.bright:
        _bright = pair;
        break;
      case TextBrightness.soft:
        _soft = pair;
        break;
      case TextBrightness.dim:
        _dim = pair;
        break;
    }
    return pair;
  }

  static Widget scope(Widget child) {
    final pair = resolve();
    return Theme(
      data: pair.material,
      child: AppThemeScope(
        theme: pair.app,
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}
