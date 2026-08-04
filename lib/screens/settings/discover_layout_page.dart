import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';

/// One selectable Discover layout.
class DiscoverLayoutChoice {
  final String value;
  final String label;
  final String subtitle;
  const DiscoverLayoutChoice(this.value, this.label, this.subtitle);
}

const List<DiscoverLayoutChoice> kDiscoverLayoutChoices = [
  DiscoverLayoutChoice(
    'grid',
    'Grid',
    'Detail rail beside a wall of posters — the most titles on screen',
  ),
  DiscoverLayoutChoice(
    'stage',
    'Stage',
    'Full-screen art and trailers, one bottom shelf — art first',
  ),
];

/// Row caption for the current choice (rail subtitle in TV settings).
String discoverLayoutLabel(String layout) {
  for (final c in kDiscoverLayoutChoices) {
    if (c.value == layout) return c.label;
  }
  return 'Stage';
}

/// Android TV "Discover Layout" picker.
///
/// Its own page (like Home Layout and Screen Size) rather than inline rows so
/// it's reachable from Settings search. Applies live: the picker fires
/// [MainPageBridge.discoverLayoutChanged] and the Discover tab rebuilds — no
/// restart needed.
class DiscoverLayoutPage extends StatefulWidget {
  const DiscoverLayoutPage({super.key});

  @override
  State<DiscoverLayoutPage> createState() => _DiscoverLayoutPageState();
}

class _DiscoverLayoutPageState extends State<DiscoverLayoutPage> {
  bool _loading = true;

  /// Placeholder until [_load] lands — must match StorageService's unset
  /// default, or the checked row jumps on first paint.
  String _layout = 'stage';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'discover-layout-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('discover_layout_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final layout = await StorageService.getDiscoverLayout();
    if (!mounted) return;
    setState(() {
      _layout = layout;
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
    if (value == _layout) return;
    setState(() => _layout = value);
    await StorageService.setDiscoverLayout(value);
    // Live-apply: the Discover tab re-reads the pref and rebuilds.
    MainPageBridge.discoverLayoutChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Discover Layout',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Discover Layout',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.explore_rounded,
                  title: 'Discover Layout',
                  subtitle: 'How the Discover tab browses on this TV',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kDiscoverLayoutChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies immediately — press Back and switch to the Discover '
                  'tab to see it. Both layouts keep the same filter line, and '
                  'Stage shows the focused title on the whole screen instead '
                  'of in a side rail.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: kSettingsDim,
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
  Widget _optionRow(DiscoverLayoutChoice choice) {
    final bool active = _layout == choice.value;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? const Icon(Icons.check_rounded, size: 20, color: kSettingsAccent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.value),
    );
  }
}
