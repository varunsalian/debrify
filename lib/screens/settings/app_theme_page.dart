import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_controller.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/platform_util.dart';
import '../../widgets/detail/theme/detail_theme.dart';
import '../../widgets/detail/theme/detail_themes.dart';
import 'detail_theme_page.dart' show kDetailThemesShipped;

/// Row caption for the Appearance list.
String appThemeLabel(String id) =>
    id == AppThemes.legacyId ? 'Debrify Classic' : DetailThemes.byId(id).label;

/// App-wide theme picker (`app_theme`) — and the Foundation's vertical proof.
///
/// This page is the first surface migrated to the token layer: every colour
/// it paints comes from [AppThemeScope] (its settings subprofile) or from the
/// adapter-built `ThemeData` — no `kSettings*` constants, no literals. Under
/// `Debrify Classic` the tokens pin the same values those constants hold, so
/// it is indistinguishable from its neighbours; under a real theme it
/// restyles in place as you pick, light themes included.
class AppThemePage extends StatefulWidget {
  const AppThemePage({super.key});

  @override
  State<AppThemePage> createState() => _AppThemePageState();
}

class _AppThemePageState extends State<AppThemePage> {
  final FocusNode _firstCardMarker = FocusNode(
    debugLabel: 'app-theme-first-card',
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
    AnalyticsService.screenView('app_theme_settings');
    // isTelevision, not isAndroidTvCached: Apple TV reaches this page through
    // the same two-pane Settings shell and needs the same initial card focus.
    if (PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final primary = FocusManager.instance.primaryFocus;
        if (primary != null && primary is! FocusScopeNode) return;
        _firstCardMarker.traversalDescendants.firstOrNull?.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _firstCardMarker.dispose();
    super.dispose();
  }

  Future<void> _select(String id) async {
    if (id == AppThemeController.instance.id) return;
    await AppThemeController.instance.select(id);
    // The root rebuild re-themes this page through the scope; the setState is
    // only for the radio glyphs, which key off the controller's id.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final selected = AppThemeController.instance.id;

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: app.core.tx,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.format_paint_rounded,
                          size: 22, color: t.accent2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'App Theme',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: app.core.tx,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'One look for the whole app — experimental. The video '
                      'player keeps its own dark theme, so controls stay '
                      'readable over any video.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: t.dim,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Focus(
                    focusNode: _firstCardMarker,
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.panel,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.line),
                      ),
                      child: Column(
                        children: [
                          _optionRow(
                            app: app,
                            id: AppThemes.legacyId,
                            label: 'Debrify Classic',
                            subtitle:
                                'Today\'s Debrify, untouched. Details pages '
                                'keep their own theme choice.',
                            selected: selected == AppThemes.legacyId,
                            swatches: null,
                          ),
                          for (final choice in _choices)
                            _optionRow(
                              app: app,
                              id: choice.id,
                              label: choice.label,
                              subtitle: choice.subtitle,
                              selected: selected == choice.id,
                              swatches: [
                                choice.ground,
                                choice.accent,
                                choice.state,
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Picking a theme here also sets the Details Theme to '
                      'match, so movie and series pages agree with the app. '
                      'Switching back to Debrify Classic keeps that details '
                      'choice.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: t.dim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required AppTheme app,
    required String id,
    required String label,
    required String subtitle,
    required bool selected,
    required List<Color>? swatches,
  }) {
    final t = app.settings;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _select(id),
        borderRadius: BorderRadius.circular(14),
        focusColor: t.accent.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? t.accent2 : t.dim,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: app.core.tx,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: t.dim,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (swatches != null) ...[
                const SizedBox(width: 10),
                for (final c in swatches) ...[
                  _swatch(c, t),
                  const SizedBox(width: 4),
                ],
              ],
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.check_rounded, size: 20, color: t.accent2),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _swatch(Color c, SettingsTokens t) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: t.line),
    ),
  );
}
