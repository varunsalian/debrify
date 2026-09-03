import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/play_loader_style.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import 'stream_badges_settings_page.dart';
import 'widgets/settings_widgets.dart';

/// Row caption for the current choice (Appearance row subtitle).
String playLoaderStyleLabel(String style) =>
    PlayLoaderStyleController.labelFor(style);

/// Play loader look picker (`play_loader_style`).
///
/// The loader is the screen between pressing Play and the picture starting:
/// Marquee (the default) paints the title's backdrop and logo art with the
/// resolve stages on a rail; Classic is the poster-and-checklist card.
///
/// The play path reads the choice synchronously from
/// [PlayLoaderStyleController.cached], which this page updates on tap — so a
/// change applies to the very next play, no restart.
class PlayLoaderStylePage extends StatefulWidget {
  const PlayLoaderStylePage({super.key});

  @override
  State<PlayLoaderStylePage> createState() => _PlayLoaderStylePageState();
}

class _PlayLoaderStylePageState extends State<PlayLoaderStylePage> {
  bool _loading = true;
  String _style = PlayLoaderStyleController.defaultStyle;

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'play-loader-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('play_loader_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await PlayLoaderStyleController.warm();
    if (!mounted) return;
    setState(() {
      _style = PlayLoaderStyleController.cached;
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
    await PlayLoaderStyleController.select(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Play Loader',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Play Loader',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Play Loader',
                  subtitle:
                      'What you see between pressing Play and the picture '
                      'starting',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in PlayLoaderStyleController.options)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Marquee uses the backdrop and logo art the details page '
                  'already loaded. Titles without that artwork fall back to '
                  'the poster, exactly like Classic.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
                ),
                const SizedBox(height: 24),
                SettingsSection(
                  title: 'Sources',
                  children: [
                    SettingsTile(
                      icon: Icons.sell_rounded,
                      title: 'Stream badges',
                      subtitle:
                          'Import Nuvio-style badge rules for the source list',
                      onTap: () => pushSettingsPage(
                        context,
                        const StreamBadgesSettingsPage(),
                      ),
                    ),
                  ],
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
  Widget _optionRow(({String id, String label, String blurb}) choice) {
    final t = AppThemeScope.of(context).settings;
    final bool active = _style == choice.id;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.blurb,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.id),
    );
  }
}
