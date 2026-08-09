import '../../theme/app_looks.dart';
import 'package:flutter/material.dart';

import '../../services/analytics_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_theme_controller.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/premium_looks.dart';
import '../../utils/platform_util.dart';
import '../../widgets/detail/theme/detail_theme.dart';
import '../../widgets/detail/theme/detail_themes.dart';
import 'detail_page_style_page.dart' show effectiveDetailPageStyle;
import 'detail_theme_page.dart' show kDetailThemesShipped;
import 'widgets/settings_widgets.dart' show SettingsSectionLabel;

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
    for (final t in DetailThemes.catalogue)
      if (kDetailThemesShipped.contains(t.id)) t,
  ];

  /// The two classes of theme, told apart — see the note in
  /// `detail_theme_page.dart`. A spec look restyles the app's STRUCTURE; a
  /// core theme is a palette whose vocabulary is neutral by construction.
  static List<DetailTheme> get _complete =>
      [for (final t in _choices) if (PremiumLooks.byId(t.id) != null) t];

  static List<DetailTheme> get _palettes =>
      [for (final t in _choices) if (PremiumLooks.byId(t.id) == null) t];

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
    // Tell an in-flight Look apply that a human just chose this key, so it
    // does not stamp over the choice. See theme/app_looks.dart.
    LookApplier.noteExternalWrite('app_theme');
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
                  // Picking a theme while Classic is the details layout looks
                  // like it did nothing on the page most people judge the app
                  // by. Said HERE rather than only on the Details Page picker,
                  // because this is the screen where the expectation is set.
                  if (effectiveDetailPageStyle(
                        StorageService.detailPageStyleCached,
                      ) ==
                      'classic') ...[
                    const SizedBox(height: 18),
                    _classicNotice(app),
                  ],
                  const SizedBox(height: 20),
                  Focus(
                    focusNode: _firstCardMarker,
                    canRequestFocus: false,
                    skipTraversal: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Classic leads and sits on its own: it is not a look
                        // OR a palette, it is the absence of both.
                        _group(app, [
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
                        ]),
                        _heading(app, 'Complete looks',
                            'Change structure, focus and motion — not just '
                                'colour.'),
                        _group(app, [
                          for (final choice in _complete)
                            _row(app, choice, selected),
                        ]),
                        _heading(app, 'Palettes',
                            'Recolour the app; layout and motion stay as they '
                                'are.'),
                        _group(app, [
                          for (final choice in _palettes)
                            _row(app, choice, selected),
                        ]),
                      ],
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

  /// Why a theme appears to do nothing on detail pages.
  ///
  /// Classic is the one details layout that is deliberately unthemed — it
  /// paints its own literals — so a theme picked here reaches every screen
  /// except the one the user is most likely to check first.
  Widget _classicNotice(AppTheme app) {
    final t = app.settings;
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
          Icon(Icons.info_outline_rounded, size: 17, color: t.dim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Your Details Page is set to Classic, which keeps its own look — '
              'so themes will not apply to movie and series pages. Pick any '
              'other layout under Appearance → Details Page.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: t.dim),
            ),
          ),
        ],
      ),
    );
  }

  /// One bordered panel around a run of rows — the shape the single list had.
  Widget _group(AppTheme app, List<Widget> rows) {
    final t = app.settings;
    return Container(
      decoration: BoxDecoration(
        color: t.panel,
        borderRadius: app.shape.br(14),
        border: Border.all(color: t.line),
      ),
      child: Column(children: rows),
    );
  }

  Widget _heading(AppTheme app, String title, String blurb) {
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionLabel(title),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              blurb,
              style: TextStyle(fontSize: 12, height: 1.4, color: t.dim),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(AppTheme app, DetailTheme choice, String selected) => _optionRow(
    app: app,
    id: choice.id,
    label: choice.label,
    subtitle: choice.subtitle,
    selected: selected == choice.id,
    swatches: [choice.ground, choice.accent, choice.state],
  );

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
        borderRadius: app.shape.br(14),
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
