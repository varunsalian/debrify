import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/text_brightness.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// Row caption for the current choice (Appearance row subtitle).
String textBrightnessLabel(String pref) => TextBrightness.fromPref(pref).label;

/// App-wide text brightness picker (`text_brightness`).
///
/// Selection applies LIVE — the root rebuilds its theme on the spot, so this
/// very page dims or brightens under the user as they choose, which is all
/// the preview a brightness setting needs.
class TextBrightnessPage extends StatefulWidget {
  const TextBrightnessPage({super.key});

  @override
  State<TextBrightnessPage> createState() => _TextBrightnessPageState();
}

class _TextBrightnessPageState extends State<TextBrightnessPage> {
  // Sync-cached by the controller, so no loading state.
  TextBrightness _choice = TextBrightnessController.current;

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'text-brightness-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('text_brightness_settings');
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Don't yank focus if it already landed on a real node (only the
        // route's FocusScope holds focus while nothing is focused yet).
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _select(TextBrightness choice) async {
    if (choice == _choice) return;
    setState(() => _choice = choice);
    await TextBrightnessController.select(choice);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return SettingsPageScaffold(
      title: 'Text Brightness',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.brightness_6_rounded,
                  title: 'Text Brightness',
                  subtitle: 'How bright text is across the app',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in TextBrightness.values)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies immediately, everywhere. Buttons and text on '
                  'colored surfaces keep their designed contrast, and a few '
                  'screens with their own styling will follow in a later '
                  'update.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: t.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Radio-style row — a plain [SettingsTile] (the DPAD-proven row) with a
  /// check on the active one.
  Widget _optionRow(TextBrightness choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _choice == choice;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice),
    );
  }
}
