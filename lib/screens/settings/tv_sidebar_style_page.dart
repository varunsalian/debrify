import '../../theme/app_looks.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable TV sidebar style.
class TvSidebarStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const TvSidebarStyleChoice(this.value, this.label, this.subtitle);
}

const List<TvSidebarStyleChoice> kTvSidebarStyleChoices = [
  TvSidebarStyleChoice(
    'ghost',
    'Ghost',
    'No chrome: floating icons, white coin — the default',
  ),
  TvSidebarStyleChoice(
    'classic',
    'Classic',
    'The original liquid glass rail',
  ),
  TvSidebarStyleChoice(
    'island',
    'Island',
    'A floating glass capsule, detached from the edge',
  ),
  TvSidebarStyleChoice(
    'marquee',
    'Marquee',
    'Ghost icons at rest, an oversized text menu when opened',
  ),
  TvSidebarStyleChoice(
    'badge',
    'Badge',
    'Labelled icons; the active tab wears a white badge',
  ),
  TvSidebarStyleChoice(
    'pill',
    'Pill',
    'No rail at all — just the current tab, and content fills the screen',
  ),
];

/// Row caption for the current choice (rail subtitle in TV settings).
String tvSidebarStyleLabel(String style) {
  for (final c in kTvSidebarStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Ghost';
}

/// Android TV "Sidebar Style" picker.
///
/// Its own page (like Home Layout) so it's reachable from Settings search.
/// Applies live via [MainPageBridge.tvSidebarStyleChanged] — no restart.
/// Only the chrome changes: the LEFT-only open policy and DPAD model are
/// identical in every style.
class TvSidebarStylePage extends StatefulWidget {
  const TvSidebarStylePage({super.key});

  @override
  State<TvSidebarStylePage> createState() => _TvSidebarStylePageState();
}

class _TvSidebarStylePageState extends State<TvSidebarStylePage> {
  bool _loading = true;
  String _style = 'ghost';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-sidebar-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_sidebar_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getTvSidebarStyle();
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
    // Tell an in-flight Look apply that a human just chose this key, so it
    // does not stamp over the choice. See theme/app_looks.dart.
    LookApplier.noteExternalWrite('tv_sidebar_style');
    await StorageService.setTvSidebarStyle(value);
    // Live-apply: the app shell re-reads the pref and reskins the rail.
    MainPageBridge.tvSidebarStyleChanged?.call();
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
                  subtitle: 'How the navigation rail looks on this TV',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kTvSidebarStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies immediately. Every style opens the same way — '
                  'press LEFT at the edge of any screen.',
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
  /// check on the active one, rather than a dropdown whose overlay would have
  /// to be focus-managed on a remote.
  Widget _optionRow(TvSidebarStyleChoice choice) {
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
