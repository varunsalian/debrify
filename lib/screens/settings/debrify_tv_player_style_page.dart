import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable Debrify TV playback-screen style.
class DebrifyTvPlayerStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const DebrifyTvPlayerStyleChoice(this.value, this.label, this.subtitle);
}

const List<DebrifyTvPlayerStyleChoice> kDebrifyTvPlayerStyleChoices = [
  DebrifyTvPlayerStyleChoice(
    'cinema',
    'Cinema',
    'Poster card and serif title with a gilded spec line',
  ),
  DebrifyTvPlayerStyleChoice(
    'network',
    'Network',
    'Broadcast lower-third — channel plate, clean title, quality chips',
  ),
  DebrifyTvPlayerStyleChoice(
    'guide',
    'Guide',
    'Opaque broadcast band — channel block, now-playing cell, pool count',
  ),
  DebrifyTvPlayerStyleChoice(
    'spotlight',
    'Spotlight',
    'Frosted glass panel in the app\'s Spotlight idiom',
  ),
  DebrifyTvPlayerStyleChoice(
    'prestige',
    'Prestige',
    'The quiet one — serif title, hairline spec line, underline focus',
  ),
  DebrifyTvPlayerStyleChoice(
    'classic',
    'Legacy',
    'The previous look — top marquee bar and the labeled button strip',
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String debrifyTvPlayerStyleLabel(String style) {
  for (final c in kDebrifyTvPlayerStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Cinema';
}

/// Debrify TV playback-screen style picker (`debrify_tv_player_style`).
///
/// Android TV only — the native Debrify TV player is the only reader. The
/// pref is read once at player launch, so a change applies to the next
/// playback session — persist on tap is all that's needed.
class DebrifyTvPlayerStylePage extends StatefulWidget {
  const DebrifyTvPlayerStylePage({super.key});

  @override
  State<DebrifyTvPlayerStylePage> createState() =>
      _DebrifyTvPlayerStylePageState();
}

class _DebrifyTvPlayerStylePageState extends State<DebrifyTvPlayerStylePage> {
  bool _loading = true;
  String _style = 'cinema';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'debrify-tv-player-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('debrify_tv_player_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getDebrifyTvPlayerStyle();
    if (!mounted) return;
    setState(() {
      _style = style;
      _loading = false;
    });
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

  Future<void> _select(String value) async {
    if (value == _style) return;
    setState(() => _style = value);
    await StorageService.setDebrifyTvPlayerStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Debrify TV Player',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Debrify TV Player',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.live_tv_rounded,
                  title: 'Debrify TV Player',
                  subtitle:
                      'How the playback screen looks while a channel airs',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kDebrifyTvPlayerStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies to the next playback session. Every style shows '
                  'the fetched show or movie name instead of the release '
                  'filename.',
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
  Widget _optionRow(DebrifyTvPlayerStyleChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _style == choice.value;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.value),
    );
  }
}
