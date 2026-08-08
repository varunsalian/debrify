import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable IPTV cockpit look.
class IptvStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const IptvStyleChoice(this.value, this.label, this.subtitle);
}

const List<IptvStyleChoice> kIptvStyleChoices = [
  IptvStyleChoice(
    'command',
    'Command Center',
    'The shipped cockpit — dense guide, gold focus',
  ),
  IptvStyleChoice(
    'edition',
    'First Edition',
    'Editorial ink and serif headlines — hairline ledger, ivory focus',
  ),
  IptvStyleChoice(
    'console',
    'Master Control',
    'Broadcast console — pure black, mono numerals, amber playhead',
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String iptvStyleLabel(String style) {
  for (final c in kIptvStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Command Center';
}

/// IPTV page appearance picker (`iptv_style`).
///
/// Its own page so the Appearance section and Settings search can land on
/// the picker directly; the section inside IPTV settings keeps hosting the
/// same pref for people configuring IPTV. Persist on tap — a newly opened
/// IPTV page route loads the stored value in its initState, so no bridge
/// call is needed.
class IptvStylePage extends StatefulWidget {
  const IptvStylePage({super.key});

  @override
  State<IptvStylePage> createState() => _IptvStylePageState();
}

class _IptvStylePageState extends State<IptvStylePage> {
  bool _loading = true;
  String _style = 'command';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'iptv-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('iptv_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getIptvStyle();
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
    await StorageService.setIptvStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'IPTV Appearance',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'IPTV Appearance',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.style_rounded,
                  title: 'IPTV Appearance',
                  subtitle: 'How the IPTV page looks on TV and desktop',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kIptvStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies the next time the IPTV page opens. Phones keep '
                  'the classic list either way.',
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
  Widget _optionRow(IptvStyleChoice choice) {
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
