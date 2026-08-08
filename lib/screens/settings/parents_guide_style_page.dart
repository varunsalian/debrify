import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

class ParentsGuideStyleChoice {
  final String value;
  final String label;
  final String subtitle;

  const ParentsGuideStyleChoice(this.value, this.label, this.subtitle);
}

const List<ParentsGuideStyleChoice> kParentsGuideStyleChoices = [
  ParentsGuideStyleChoice(
    'compass',
    'Compass',
    'A severity dashboard with category signals and focused guidance',
  ),
  ParentsGuideStyleChoice(
    'classic',
    'Classic',
    'The original compact expandable category list',
  ),
];

String parentsGuideStyleLabel(String raw) =>
    raw == 'classic' ? 'Classic' : 'Compass';

class ParentsGuideStylePage extends StatefulWidget {
  const ParentsGuideStylePage({super.key});

  @override
  State<ParentsGuideStylePage> createState() => _ParentsGuideStylePageState();
}

class _ParentsGuideStylePageState extends State<ParentsGuideStylePage> {
  bool _loading = true;
  String _style = 'compass';
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'parents-guide-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('parents_guide_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getParentsGuideStyle();
    if (!mounted) return;
    setState(() {
      _style = style;
      _loading = false;
    });
    if (PlatformUtil.isAndroidTvCached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  Future<void> _select(String value) async {
    if (value == _style) return;
    setState(() => _style = value);
    await StorageService.setParentsGuideStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Parents Guide',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Parents Guide',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.family_restroom_rounded,
                  title: 'Parents Guide',
                  subtitle:
                      'How content advisories are presented on title pages',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kParentsGuideStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies the next time a Parents Guide is shown.',
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

  Widget _optionRow(ParentsGuideStyleChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final active = _style == choice.value;
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
