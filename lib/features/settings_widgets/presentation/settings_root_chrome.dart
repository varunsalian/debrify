import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Full-bleed settings room.
///
/// The vertical ground-to-pane walk is the same stage used by onboarding.
/// A restrained accent bloom gives themed Looks their identity without
/// returning to the old purple wash that sat behind every theme.
class SettingsBackground extends StatelessWidget {
  final Widget child;
  const SettingsBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (app.id != 'spotlight') {
      return Container(
        color: t.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -1.0),
                    radius: 1.2,
                    colors: [
                      app.fade(t.accent, 0x29 / 0xFF),
                      Colors.transparent,
                    ],
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
    final bottom = Color.lerp(t.bg, app.core.pane, 0.34)!.withValues(alpha: 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [t.bg.withValues(alpha: 1), bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.92, -1.08),
                  radius: 1.05,
                  colors: [app.fade(t.accent, 0.13), Colors.transparent],
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

/// Backwards-compatible root header used by loading and search surfaces.
/// New responsive roots use [SettingsRootHeader] from the Spotlight shell.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    if (app.id != 'spotlight') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage connections, search & playback',
            style: TextStyle(fontSize: 13, color: t.dim),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR SPACE',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 2.1,
            color: t.accent.withValues(alpha: 0.88),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Settings',
          // No color: inherits onSurface via the ambient DefaultTextStyle,
          // so it follows Appearance → Text Brightness.
          style: TextStyle(
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Services, screens and playback—tuned in one place.',
          style: TextStyle(fontSize: 12, height: 1.45, color: t.dim),
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
    final app = AppThemeScope.of(context);
    final spotlight = app.id == 'spotlight';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: spotlight ? 'JetBrainsMono' : null,
          fontSize: spotlight ? 9 : 12,
          fontWeight: spotlight ? FontWeight.w700 : FontWeight.w800,
          letterSpacing: spotlight ? 1.55 : 0.7,
          color: color ?? app.settings.dim,
        ),
      ),
    );
  }
}
