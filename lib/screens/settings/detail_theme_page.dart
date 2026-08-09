import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/detail/theme/detail_theme.dart';
import '../../widgets/detail/theme/detail_themes.dart';
import 'detail_page_style_page.dart' show effectiveDetailPageStyle;
import '../../theme/app_theme_scope.dart';
import 'widgets/settings_widgets.dart';

/// Every theme this build can actually draw.
///
/// Narrower than [StorageService.kDetailThemes], which accepts all twenty so a
/// choice written by a newer build survives a downgrade. Dispatch, the Settings
/// subtitle and the picker's selected state all read [effectiveDetailTheme]
/// rather than the raw value.
///
/// ── The two light-ground themes are withheld for now ──────────────────────
///
/// `broadsheet` (#F3EFE7) and `concrete` (#C9C7C1) are the only cores whose
/// ground is light — `AppTheme.fromDetail` classifies them by
/// `ground.computeLuminance() > 0.5`, and no other core comes close.
///
/// **Bug:** text stays light-on-light and is unreadable on them. The token
/// layer flips correctly, but the screens still carrying hardcoded light text
/// literals never go through it, so they don't follow the ground when it turns
/// pale. Every dark theme hides this — a light-on-dark literal happens to be
/// right — which is why it only shows up on these two.
///
/// Withheld HERE rather than dropped from [DetailThemes.all] so the fallbacks
/// stay graceful: [effectiveDetailTheme] narrows a stored `broadsheet` to
/// `signal`, `AppThemes.byId` narrows it to legacy, and nothing is rewritten
/// on disk. Anyone already on one lands on a readable theme, and gets theirs
/// back the moment these are re-listed.
///
/// Re-enable both once the remaining literals read from the token layer.
const Set<String> kDetailThemesShipped = {
  'signal',
  'noir',
  // 'broadsheet', // light ground — unreadable text, see note above
  'phosphor',
  'aurora',
  // 'concrete',   // light ground — unreadable text, see note above
  'velvet',
  'blueprint',
  'broadcast',
  'sepia',
  'obsidian',
  'halo',
  'prestige',
  'deep_field',
  'graphite',
  'vault',
  'spectrum',
  'verdant',
  'frost',
  'cinemascope',
};

/// The stored value narrowed to what this build can render. Never persists.
String effectiveDetailTheme(String raw) =>
    kDetailThemesShipped.contains(raw) ? raw : 'signal';

/// Row caption for the Appearance list.
String detailThemeLabel(String raw) =>
    DetailThemes.byId(effectiveDetailTheme(raw)).label;

/// Details-page theme picker (`detail_theme`).
///
/// Orthogonal to the layout picker: the layout says where things are, the theme
/// says what they look like. Classic is deliberately unthemed, and the page
/// says so when it is the active layout — otherwise a user picks a theme, sees
/// nothing change, and reports a bug.
class DetailThemePage extends StatefulWidget {
  const DetailThemePage({super.key});

  @override
  State<DetailThemePage> createState() => _DetailThemePageState();
}

class _DetailThemePageState extends State<DetailThemePage> {
  bool _loading = true;
  String _theme = 'signal';
  bool _classicActive = false;

  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'detail-theme-first-card',
    skipTraversal: true,
    canRequestFocus: false,
  );

  static List<DetailTheme> get _choices => [
    for (final t in DetailThemes.all)
      if (kDetailThemesShipped.contains(t.id)) t,
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('detail_theme_settings');
    _load();
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final theme = await StorageService.getDetailTheme();
    final style = await StorageService.getDetailPageStyle();
    if (!mounted) return;
    setState(() {
      _theme = effectiveDetailTheme(theme);
      _classicActive = effectiveDetailPageStyle(style) == 'classic';
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
    if (value == _theme) return;
    setState(() => _theme = value);
    await StorageService.setDetailTheme(value);
  }

  @override
  Widget build(BuildContext context) {
    // `st` rather than `t`: this page's rows already bind `t` to a DetailTheme.
    final st = AppThemeScope.of(context).settings;
    if (_loading) {
      return const SettingsPageScaffold(
        title: 'Details Theme',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return SettingsPageScaffold(
      title: 'Details Theme',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kSettingsMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsPageHeader(
                  icon: Icons.palette_rounded,
                  title: 'Details Theme',
                  subtitle:
                      'The colours, type and shapes a movie or series page is '
                      'drawn in',
                ),
                if (_classicActive) ...[
                  const SizedBox(height: 16),
                  _classicNotice(),
                ],
                const SizedBox(height: 24),
                Focus(
                  focusNode: _firstCardMarker,
                  canRequestFocus: false,
                  skipTraversal: true,
                  child: SettingsSection(
                    title: '',
                    children: [for (final t in _choices) _optionRow(t)],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Applies the next time you open a movie or series — on this '
                  'device and on Android TV.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: st.dim,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Picking a theme while Classic is the layout would appear to do nothing.
  /// Say so rather than let it read as a bug.
  Widget _classicNotice() {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: app.fade(app.core.tx, 0.05),
        borderRadius: app.shape.br(10),
        border: Border.all(color: app.fade(app.core.tx, 0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 17, color: app.settings.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your details page is set to Classic, which keeps its own look. '
              'Pick any alternate layout under Details Page to see a theme '
              'applied.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: app.settings.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(DetailTheme t) {
    final st = AppThemeScope.of(context).settings;
    final active = _theme == t.id;
    return SettingsTile(
      icon: active
          ? Icons.radio_button_checked_rounded
          : Icons.radio_button_unchecked_rounded,
      title: t.label,
      subtitle: t.subtitle,
      // Ground, accent and state at a glance — the three that actually decide
      // whether a theme is for you.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _swatch(t.ground),
          const SizedBox(width: 4),
          _swatch(t.accent),
          const SizedBox(width: 4),
          _swatch(t.state),
          if (active) ...[
            const SizedBox(width: 10),
            Icon(Icons.check_rounded, size: 20, color: st.accent2),
          ],
        ],
      ),
      onTap: () => _select(t.id),
    );
  }

  Widget _swatch(Color c) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
    ),
  );
}
