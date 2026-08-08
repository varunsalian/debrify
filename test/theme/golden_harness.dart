import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/legacy_theme_boundary.dart';

/// Golden infrastructure for the theme rollout.
///
/// Goldens render with the test framework's deterministic font (block glyphs
/// — [disableRuntimeFonts] swaps the GoogleFonts wrapper out entirely), so
/// they pin COLOUR and LAYOUT, not typography. That is the point: the risk
/// class this harness exists for is "a token swap changed a colour or an
/// alpha composite", which block glyphs show perfectly.
void disableRuntimeFonts() {
  GoogleFonts.config.allowRuntimeFetching = false;
  // No Inter asset exists in the test bundle, so any ThemeData build through
  // GoogleFonts logs a font-load "Error:" block per style — noise that buries
  // real failures. The adapter's test flag uses the raw skeleton instead;
  // both resolve to the same deterministic test font at render time.
  AppThemeAdapter.debugUseTestTypography = true;
}

/// Pump [child] under a given theme id, wired exactly like production:
/// adapter-built ThemeData on MaterialApp, token scope above the child.
///
/// [preset] drives the GLOBAL TextBrightnessController for the pump's
/// lifetime — LegacyThemeBoundary reads the controller's legacy cache, so a
/// harness-local preset would render a themed pane at one preset beside a
/// frozen pane at another, and the dim golden would pin nothing about frozen
/// surfaces following the preset.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  required String themeId,
  TextBrightness preset = TextBrightness.bright,
  Size surface = const Size(900, 1200),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previousPreset = TextBrightnessController.notifier.value;
  TextBrightnessController.notifier.value = preset;
  addTearDown(() => TextBrightnessController.notifier.value = previousPreset);

  final AppTheme theme;
  final ThemeData data;
  if (themeId == AppThemes.legacyId) {
    theme = AppThemes.legacy;
    data = AppThemeAdapter.legacy(preset);
  } else {
    final resolved = AppThemeAdapter.resolveCoreText(
      AppThemes.byId(themeId).core,
      preset,
    );
    theme = AppTheme.fromDetail(resolved);
    data = AppThemeAdapter.themed(theme, preset);
  }

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: data,
    builder: (context, c) => AppThemeScope(theme: theme, child: c!),
    home: child,
  ));
  await tester.pumpAndSettle();
}

/// The boundary demo: a themed pane and a frozen pane side by side — the
/// Foundation gate's "themed and frozen destination rendering side by side",
/// as a reproducible pixel artifact. Every colour comes from tokens or from
/// `Theme.of`, so the demo exercises the scope, the adapter and the boundary
/// at once.
class BoundaryDemo extends StatelessWidget {
  const BoundaryDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _DemoPane(caption: 'themed')),
          Expanded(
            child: LegacyThemeBoundary(
              child: _DemoPane(caption: 'frozen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPane extends StatelessWidget {
  final String caption;

  const _DemoPane({required this.caption});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final theme = Theme.of(context);
    return ColoredBox(
      color: t.bg,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption,
                style: TextStyle(
                  color: app.core.tx,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Panel',
                      style: TextStyle(color: app.core.tx, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Dim caption',
                      style: TextStyle(color: t.dim, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _chip(t.success),
                    const SizedBox(width: 6),
                    _chip(t.warning),
                    const SizedBox(width: 6),
                    _chip(t.danger),
                    const SizedBox(width: 6),
                    _chip(t.accent),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Material controls — these read ThemeData, proving the adapter
            // (and the boundary's frozen ThemeData) on the same image.
            ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            const SizedBox(height: 8),
            Switch(value: true, onChanged: (_) {}),
            const SizedBox(height: 8),
            Text('onSurface body text', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            const TextField(
              decoration: InputDecoration(hintText: 'Input'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(Color c) => Container(
        width: 22,
        height: 14,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(4),
        ),
      );
}
