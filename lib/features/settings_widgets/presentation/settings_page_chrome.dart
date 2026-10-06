import 'package:debrify/features/settings_widgets/presentation/settings_page_theme.dart';
import 'package:debrify/features/settings_widgets/presentation/settings_root_chrome.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Standard scaffold for every settings subpage: applies [settingsPageTheme],
/// paints the [SettingsBackground] wash under a transparent AppBar, and keeps
/// the page's own body/scroll untouched.
class SettingsPageScaffold extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final PreferredSizeWidget? appBarBottom;
  final bool? resizeToAvoidBottomInset;

  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.leading,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.appBarBottom,
    this.resizeToAvoidBottomInset,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: settingsPageTheme(context),
      child: SettingsBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          // AppBar chrome (transparent bg, zero elevation) comes from
          // settingsPageTheme.appBarTheme — single source of truth.
          appBar: AppBar(
            title: Text(title),
            leading: leading,
            actions: actions,
            bottom: appBarBottom,
          ),
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
        ),
      ),
    );
  }
}

/// Flat page hero for subpages: accent-tinted icon chip + title + subtitle.
/// Replaces the old gradient `primaryContainer` header cards.
class SettingsPageHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const SettingsPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: t.accent2, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                // No color: inherits the ambient bodyMedium color, which is
                // onSurface — and so follows Appearance → Text Brightness.
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, height: 1.4, color: t.dim),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Quiet informational banner (replaces the old secondaryContainer info
/// boxes). [tone] tints it: accent (default), warning amber, or danger red.
enum SettingsBannerTone { info, warning, danger, success }

class SettingsInfoBanner extends StatelessWidget {
  final String text;
  final IconData icon;
  final SettingsBannerTone tone;

  const SettingsInfoBanner({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.tone = SettingsBannerTone.info,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final Color c = switch (tone) {
      SettingsBannerTone.info => t.accent2,
      SettingsBannerTone.warning => t.warning,
      SettingsBannerTone.danger => t.danger,
      SettingsBannerTone.success => t.success,
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: app.shape.br(12),
        border: Border.all(color: c.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: app.fade(app.core.tx, 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
