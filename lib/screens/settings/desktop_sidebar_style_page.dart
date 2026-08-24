import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme_scope.dart';
import 'widgets/settings_widgets.dart';
import 'sidebar_customization_page.dart';

/// One selectable desktop/tablet sidebar style.
class DesktopSidebarStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const DesktopSidebarStyleChoice(this.value, this.label, this.subtitle);
}

const List<DesktopSidebarStyleChoice> kDesktopSidebarStyleChoices = [
  DesktopSidebarStyleChoice(
    'rail',
    'Rail',
    'The fixed icon rail down the left — the default',
  ),
  DesktopSidebarStyleChoice(
    'pill',
    'Pill',
    'No rail at all — a floating pill shows the current tab, and '
        'clicking it opens the menu over the page',
  ),
];

/// Row caption for the current choice.
String desktopSidebarStyleLabel(String style) {
  for (final c in kDesktopSidebarStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Rail';
}

/// Desktop / tablet "Sidebar Style" picker — the pointer-world sibling of the
/// TV picker. Its own page (like Home Layout) so it's reachable from Settings
/// search. Applies live via [MainPageBridge.desktopSidebarStyleChanged] — no
/// restart. Only the wide (≥600) layout reads the pref; phones keep their
/// bottom navigation whatever is chosen here.
class DesktopSidebarStylePage extends StatefulWidget {
  const DesktopSidebarStylePage({super.key});

  @override
  State<DesktopSidebarStylePage> createState() =>
      _DesktopSidebarStylePageState();
}

class _DesktopSidebarStylePageState extends State<DesktopSidebarStylePage> {
  bool _loading = true;
  String _style = 'rail';

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('desktop_sidebar_style_settings');
    _load();
  }

  Future<void> _load() async {
    final style = await StorageService.getDesktopSidebarStyle();
    if (!mounted) return;
    setState(() {
      _style = style;
      _loading = false;
    });
  }

  Future<void> _select(String value) async {
    if (value == _style) return;
    setState(() => _style = value);
    await StorageService.setDesktopSidebarStyle(value);
    // Live-apply: the shell re-reads the pref and swaps the chrome.
    MainPageBridge.desktopSidebarStyleChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Sidebar Style',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Sidebar Style',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.view_sidebar_rounded,
                  title: 'Sidebar Style',
                  subtitle:
                      'How navigation is drawn in wide windows — desktop '
                      'and tablets',
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: '',
                  children: [
                    for (final choice in kDesktopSidebarStyleChoices)
                      _optionRow(choice),
                  ],
                ),
                const SizedBox(height: 18),
                SettingsSection(
                  title: 'Items',
                  children: [
                    SettingsTile(
                      icon: Icons.low_priority_rounded,
                      title: 'Order & Names',
                      subtitle:
                          'Rearrange destinations and rename sidebar labels',
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => pushSettingsPage(
                        context,
                        const SidebarCustomizationPage(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies immediately. Phones keep their bottom '
                  'navigation; the TV rail has its own style in TV '
                  'settings.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Radio-style row — the same grammar as the TV sidebar picker.
  Widget _optionRow(DesktopSidebarStyleChoice choice) {
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
