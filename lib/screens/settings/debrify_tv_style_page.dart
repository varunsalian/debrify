import '../../theme/app_looks.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable Debrify TV layout.
class DebrifyTvStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const DebrifyTvStyleChoice(this.value, this.label, this.subtitle);
}

const List<DebrifyTvStyleChoice> kDebrifyTvStyleChoices = [
  DebrifyTvStyleChoice(
    'grid',
    'Channel Grid',
    'The classic wall of channels — everything at once',
  ),
  DebrifyTvStyleChoice(
    'spotlight',
    'Spotlight',
    'A standing channel rail and a stage — what a channel holds, '
        'before you press Play',
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String debrifyTvStyleLabel(String style) {
  for (final c in kDebrifyTvStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Channel Grid';
}

/// Debrify TV appearance picker (`debrify_tv_style`).
///
/// Its own page so the Appearance section and Settings search can land on
/// the picker directly. Persist on tap — tabs are keyed by index and rebuilt
/// on switch, so a newly opened Debrify TV tab reads the stored value in its
/// initState and no bridge call is needed (same reasoning as IptvStylePage).
class DebrifyTvStylePage extends StatefulWidget {
  const DebrifyTvStylePage({super.key});

  @override
  State<DebrifyTvStylePage> createState() => _DebrifyTvStylePageState();
}

class _DebrifyTvStylePageState extends State<DebrifyTvStylePage> {
  bool _loading = true;
  String _style = 'grid';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'debrify-tv-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('debrify_tv_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getDebrifyTvStyle();
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
    // Tell an in-flight Look apply that a human just chose this key, so it
    // does not stamp over the choice. See theme/app_looks.dart.
    LookApplier.noteExternalWrite('debrify_tv_style');
    await StorageService.setDebrifyTvStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Debrify TV',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Debrify TV',
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
                  title: 'Debrify TV',
                  subtitle: 'How the channels screen looks, on every device',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kDebrifyTvStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies the next time Debrify TV opens. Playback is '
                  'identical either way — this changes what the page draws, '
                  'never what it plays.',
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
  Widget _optionRow(DebrifyTvStyleChoice choice) {
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
