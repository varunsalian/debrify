import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable native TV control skin.
class TvPlayerControlsStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const TvPlayerControlsStyleChoice(this.value, this.label, this.subtitle);
}

const List<TvPlayerControlsStyleChoice> kTvPlayerControlsStyleChoices = [
  TvPlayerControlsStyleChoice(
    'marquee',
    'Marquee',
    'Editorial serif — bare glyphs, hairline progress, underline focus',
  ),
  TvPlayerControlsStyleChoice(
    'ott',
    'OTT',
    'The Apple TV dock — circular controls, focus captions, cinema scrub',
  ),
  TvPlayerControlsStyleChoice(
    'frost',
    'Frost',
    'A translucent panel floating inset from the screen edges',
  ),
  TvPlayerControlsStyleChoice(
    'broadcast',
    'Broadcast',
    'Labeled pill buttons with the show name leading, channel-ident style',
  ),
  TvPlayerControlsStyleChoice(
    'pulse',
    'Pulse',
    'Accent-glow progress and focus rings in the app indigo',
  ),
  TvPlayerControlsStyleChoice(
    'ticket',
    'Ticket',
    'Everything on one slim band — the movie keeps most of the screen',
  ),
  TvPlayerControlsStyleChoice(
    'classic',
    'Legacy',
    "Cinema Mode — the previous controls",
  ),
];

/// Row caption for the current choice (Appearance row subtitle).
String tvPlayerControlsStyleLabel(String style) {
  for (final c in kTvPlayerControlsStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Marquee';
}

/// Native TV player control-skin picker (`tv_player_controls_style`).
///
/// Android TV only — the native player is the only reader; tvOS runs the
/// Flutter player, which has one look. The pref is read once at player
/// launch, so a change applies to the next playback session — persist on
/// tap is all that's needed.
class TvPlayerControlsStylePage extends StatefulWidget {
  const TvPlayerControlsStylePage({super.key});

  @override
  State<TvPlayerControlsStylePage> createState() =>
      _TvPlayerControlsStylePageState();
}

class _TvPlayerControlsStylePageState extends State<TvPlayerControlsStylePage> {
  bool _loading = true;
  String _style = 'marquee';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-player-controls-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_player_controls_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getTvPlayerControlsStyle();
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
    await StorageService.setTvPlayerControlsStyle(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Player Controls',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Player Controls',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.tune_rounded,
                  title: 'Player Controls',
                  subtitle:
                      'The on-screen controls during playback on this TV',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in kTvPlayerControlsStyleChoices)
                        _optionRow(choice),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies to the next playback session. Live TV keeps the '
                  'Legacy controls for now.',
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
  Widget _optionRow(TvPlayerControlsStyleChoice choice) {
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
