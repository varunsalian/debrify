import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// Android TV "Screen Size" picker.
///
/// TVs report a high pixel density (a 1080p panel at density 320 hands Flutter
/// a 960x540 logical canvas), so the app is drawn large. Picking a smaller size
/// makes MainActivity report a proportionally smaller devicePixelRatio to the
/// engine, which widens the logical canvas — the same layouts simply get more
/// room. Nothing per-screen changes, and nothing applies until the next cold
/// start, because the engine is built with the factor in `onCreate`.
///
/// Its own page rather than rows inline in the TV Mode rail so the setting is
/// reachable from Settings search like every other destination.
class TvScreenSizePage extends StatefulWidget {
  const TvScreenSizePage({super.key});

  @override
  State<TvScreenSizePage> createState() => _TvScreenSizePageState();
}

class _TvScreenSizePageState extends State<TvScreenSizePage> {
  bool _loading = true;
  int _percent = StorageService.kTvUiScaleDefault;

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-screen-size-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_screen_size_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final percent = await StorageService.getTvUiScalePercent();
    if (!mounted) return;
    setState(() {
      _percent = percent;
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

  Future<void> _select(int percent) async {
    if (percent == _percent) return;
    setState(() => _percent = percent);
    await StorageService.setTvUiScalePercent(percent);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Screen size saved — restart Debrify to apply it.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Screen Size',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Screen Size',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.fit_screen_rounded,
                  title: 'Screen Size',
                  subtitle: 'How large Debrify is drawn on this TV',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kTvUiScaleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'TVs report a high pixel density, so the app is drawn large '
                  'by default. A smaller size fits more on screen without '
                  'changing any layout. Takes effect the next time Debrify '
                  'starts.',
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
  Widget _optionRow(TvUiScaleChoice choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _percent == choice.percent;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.percent),
    );
  }
}
