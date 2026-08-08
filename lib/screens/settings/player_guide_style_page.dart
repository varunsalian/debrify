import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable in-player guide look.
class PlayerGuideStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const PlayerGuideStyleChoice(this.value, this.label, this.subtitle);
}

const List<PlayerGuideStyleChoice> kPlayerGuideStyleChoices = [
  PlayerGuideStyleChoice('classic', 'Classic', "Today's look"),
  PlayerGuideStyleChoice(
    'glass',
    'Cinema Glass',
    'Translucent panels, one violet accent — modern streaming',
  ),
  PlayerGuideStyleChoice(
    'edition',
    'Midnight Edition',
    'Ink panels and serif headlines — editorial',
  ),
  PlayerGuideStyleChoice(
    'console',
    'Master Control',
    'Black instrument — mono numerals, amber machinery',
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String playerGuideStyleLabel(String style) {
  for (final c in kPlayerGuideStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Classic';
}

/// In-player guide look picker (`iptv_player_guide_style`).
///
/// Its own page so the Appearance section and Settings search can land on
/// the picker directly; the section inside IPTV settings keeps hosting the
/// same pref. Both players read the pref once at launch, so a change
/// applies to the next playback session — persist on tap is all that's
/// needed.
class PlayerGuideStylePage extends StatefulWidget {
  const PlayerGuideStylePage({super.key});

  @override
  State<PlayerGuideStylePage> createState() => _PlayerGuideStylePageState();
}

class _PlayerGuideStylePageState extends State<PlayerGuideStylePage> {
  bool _loading = true;
  String _style = 'classic';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'player-guide-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('player_guide_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getIptvPlayerGuideStyle();
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
    await StorageService.setIptvPlayerGuideStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Player Guide',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Player Guide',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.smart_display_rounded,
                  title: 'Player Guide',
                  subtitle:
                      'How the channel banner and in-player guide look '
                      'during live TV',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kPlayerGuideStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies to the next playback session — on this device '
                  'and on Android TV.',
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
  Widget _optionRow(PlayerGuideStyleChoice choice) {
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
