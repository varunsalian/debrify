import '../../theme/app_looks.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import 'widgets/settings_widgets.dart';
import '../../theme/app_theme_scope.dart';

/// One selectable TV Home layout.
class TvHomeStyleChoice {
  final String value;
  final String label;
  final String subtitle;
  const TvHomeStyleChoice(this.value, this.label, this.subtitle);
}

const List<TvHomeStyleChoice> kTvHomeStyleChoices = [
  TvHomeStyleChoice(
    'spotlight',
    'Spotlight',
    'Full-bleed hero you can page through, shelves on a flat ground',
  ),
  TvHomeStyleChoice(
    'canvas',
    'Canvas',
    'Full-screen art and trailers, one bottom shelf — the default',
  ),
  TvHomeStyleChoice(
    'classic',
    'Classic',
    'Hero spotlight with scrolling rows',
  ),
  TvHomeStyleChoice(
    'atrium',
    'Atrium',
    'Split screen — details on the left, art and two rows of posters right',
  ),
  TvHomeStyleChoice(
    'mosaic',
    'Mosaic',
    'A wall of posters, no hero — the lightest layout',
  ),
  TvHomeStyleChoice(
    'promenade',
    'Promenade',
    'Centred art with a wide strip that slides through the middle',
  ),
  TvHomeStyleChoice(
    'deck',
    'Deck',
    'The trailer plays in a card, with the next titles stacked behind it',
  ),
  TvHomeStyleChoice(
    'tonight',
    'Tonight',
    'Resume first — a big Continue card, an Up Next queue, one row below',
  ),
];

/// Row caption for the current choice (rail subtitle in TV settings).
String tvHomeStyleLabel(String style) {
  for (final c in kTvHomeStyleChoices) {
    if (c.value == style) return c.label;
  }
  return 'Canvas';
}

/// The stored style narrowed to what an off-TV Home can render.
///
/// Phones, tablets and desktop draw exactly two layouts — Classic and
/// Spotlight; the other six are DPAD stage layouts whose focus topology has
/// no touch equivalent. The stored pref is shared with TV and is **never
/// rewritten** here: a fresh install carries the TV default `'canvas'`, which
/// this maps to Classic for display, selection and dispatch alike — while a
/// TV signing into the same account keeps its Canvas.
String effectiveOffTvHomeStyle(String raw) =>
    raw == 'spotlight' ? 'spotlight' : 'classic';

/// The choices an off-TV picker offers — see [effectiveOffTvHomeStyle].
List<TvHomeStyleChoice> get kOffTvHomeStyleChoices => [
      for (final c in kTvHomeStyleChoices)
        if (c.value == 'spotlight' || c.value == 'classic') c,
    ];

/// Android TV "Home Layout" picker.
///
/// Its own page (like Screen Size) rather than inline rows so it's reachable
/// from Settings search. Applies live: the picker fires
/// [MainPageBridge.tvHomeStyleChanged] and the Home board rebuilds — no
/// restart needed.
class TvHomeStylePage extends StatefulWidget {
  const TvHomeStylePage({super.key});

  @override
  State<TvHomeStylePage> createState() => _TvHomeStylePageState();
}

class _TvHomeStylePageState extends State<TvHomeStylePage> {
  bool _loading = true;
  String _style = 'canvas';

  /// Non-focusable marker around the options card; used on TV to hand entry
  /// focus to its first focusable descendant (the first option row).
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'tv-home-style-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('tv_home_style_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final style = await StorageService.getTvHomeStyle();
    if (!mounted) return;
    setState(() {
      _style = style;
      _loading = false;
    });
    // isTelevision, not isAndroidTvCached: Apple TV needs the same entry-focus
    // seed or the page opens with nothing actionable focused.
    if (PlatformUtil.isTelevision) {
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

  Future<void> _select(String value, String activeValue) async {
    // Compared against the RESOLVED active value, not the raw pref: off-TV a
    // stored 'canvas' displays as Classic selected, and re-tapping that row
    // must be a no-op — writing 'classic' over 'canvas' would silently change
    // what a TV renders for no visible reason here.
    if (value == activeValue) return;
    setState(() => _style = value);
    // Tell an in-flight Look apply that a human just chose this key, so it
    // does not stamp over the choice. See theme/app_looks.dart.
    LookApplier.noteExternalWrite('tv_home_style');
    await StorageService.setTvHomeStyle(value);
    // Live-apply: the Home board re-reads the pref and rebuilds.
    MainPageBridge.tvHomeStyleChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Home Layout',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Off-TV the page offers the two layouts the platform can draw, and the
    // active radio reflects the RESOLVED style — a stored 'canvas' (the TV
    // default) selects Classic here rather than leaving no row selected.
    final tv = PlatformUtil.isTelevision;
    final choices = tv ? kTvHomeStyleChoices : kOffTvHomeStyleChoices;
    final active = tv ? _style : effectiveOffTvHomeStyle(_style);

    return SettingsPageScaffold(
      title: 'Home Layout',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsPageHeader(
                  icon: Icons.view_quilt_rounded,
                  title: 'Home Layout',
                  subtitle: tv
                      ? 'How the Home screen is arranged on this TV'
                      : 'How the Home tab is arranged on this device',
                ),
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [
                      for (final choice in choices) _optionRow(choice, active),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  tv
                      ? 'Applies immediately — press Back and switch to the '
                          'Home tab to see it. The Search tab keeps the '
                          'classic layout.'
                      : 'Applies immediately — switch to the Home tab to '
                          'see it.',
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
  Widget _optionRow(TvHomeStyleChoice choice, String activeValue) {
    final t = AppThemeScope.of(context).settings;
    final bool active = activeValue == choice.value;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: choice.label,
      subtitle: choice.subtitle,
      trailing: active
          ? Icon(Icons.check_rounded, size: 20, color: t.accent2)
          : const SizedBox.shrink(),
      onTap: () => _select(choice.value, activeValue),
    );
  }
}
