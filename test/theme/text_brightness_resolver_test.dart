import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';

import 'golden_harness.dart' show disableRuntimeFonts;

/// WCAG contrast ratio between two OPAQUE colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _flatten(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(disableRuntimeFonts);

  group('resolveCoreText calibration', () {
    // The themed resolver must reproduce the legacy fixed greys (within
    // rounding — the legacy values carry a slight cool tint the proportional
    // rule deliberately drops) when applied to a white-on-black core. That is
    // the consistency proof between the two text-brightness paths.
    test('soft on a white-on-black core ≈ legacy soft grey', () {
      final core = DetailThemes.signal; // tx white, ground #0B0B0E
      final resolved =
          AppThemeAdapter.resolveCoreText(core, TextBrightness.soft);
      final legacy = TextBrightness.soft.primary!;
      expect((resolved.tx.r * 255 - legacy.r * 255).abs(), lessThan(8));
      expect((resolved.tx.g * 255 - legacy.g * 255).abs(), lessThan(8));
      expect((resolved.tx.b * 255 - legacy.b * 255).abs(), lessThan(12));
    });

    test('dim on a white-on-black core ≈ legacy dim grey', () {
      final core = DetailThemes.signal;
      final resolved =
          AppThemeAdapter.resolveCoreText(core, TextBrightness.dim);
      final legacy = TextBrightness.dim.primary!;
      expect((resolved.tx.r * 255 - legacy.r * 255).abs(), lessThan(8));
      expect((resolved.tx.g * 255 - legacy.g * 255).abs(), lessThan(8));
      expect((resolved.tx.b * 255 - legacy.b * 255).abs(), lessThan(14));
    });

    test('bright is the identity', () {
      final core = DetailThemes.broadsheet;
      expect(
        identical(
          AppThemeAdapter.resolveCoreText(core, TextBrightness.bright),
          core,
        ),
        isTrue,
      );
    });
  });

  group('contrast cross-product: every theme × every preset', () {
    // The rollout plan's exit criterion: legible primary text on every
    // shipped theme under every text-brightness preset — the light themes are
    // exactly the case the legacy fixed-grey pass failed.
    for (final core in DetailThemes.all) {
      for (final preset in TextBrightness.values) {
        test('${core.id} × ${preset.value}', () {
          final resolved = AppThemeAdapter.resolveCoreText(core, preset);
          final ground = core.ground.withValues(alpha: 1);
          final primary = _flatten(resolved.tx, ground);
          expect(_contrast(primary, ground), greaterThanOrEqualTo(4.5),
              reason: 'primary text on ${core.id} under ${preset.value}');
          // Secondary text: the AA large-text floor. tx2 is untouched by the
          // resolver, but must still survive every ground it ships on.
          final secondary = _flatten(resolved.tx2, ground);
          expect(_contrast(secondary, ground), greaterThanOrEqualTo(3.0),
              reason: 'secondary text on ${core.id} under ${preset.value}');
        });
      }
    }

    test('themed ThemeData carries the resolved text into onSurface', () {
      for (final core in DetailThemes.all) {
        for (final preset in TextBrightness.values) {
          final resolvedCore = AppThemeAdapter.resolveCoreText(core, preset);
          final app = AppTheme.fromDetail(resolvedCore);
          final data = AppThemeAdapter.themed(app, preset);
          expect(data.colorScheme.onSurface, resolvedCore.tx,
              reason: '${core.id} × ${preset.value}');
          expect(data.brightness, app.brightness,
              reason: '${core.id} × ${preset.value}');
        }
      }
    });
  });

  group('subprofile derivation follows the resolved core', () {
    test('settings.dim derives from resolved tx, not raw tx', () {
      final raw = DetailThemes.broadsheet;
      final resolved = AppThemeAdapter.resolveCoreText(raw, TextBrightness.dim);
      final app = AppTheme.fromDetail(resolved);
      expect(app.settings.dim, resolved.tx.withValues(alpha: 0.46));
    });
  });

  group('legacy path is byte-identical to the shipped construction', () {
    test('bright preset returns the untouched base', () {
      final a = AppThemeAdapter.legacy(TextBrightness.bright);
      expect(a.colorScheme.onSurface, Colors.white);
      expect(a.colorScheme.surface, const Color(0xFF06080F));
      expect(a.brightness, Brightness.dark);
    });

    test('soft/dim retarget exactly the legacy fields', () {
      final soft = AppThemeAdapter.legacy(TextBrightness.soft);
      expect(soft.colorScheme.onSurface, TextBrightness.soft.primary);
      expect(soft.colorScheme.onSurfaceVariant,
          AppThemeAdapter.legacy(TextBrightness.bright).colorScheme
              .onSurfaceVariant,
          reason: 'soft leaves onSurfaceVariant alone (preset.secondary is '
              'null for soft)');
      final dim = AppThemeAdapter.legacy(TextBrightness.dim);
      expect(dim.colorScheme.onSurface, TextBrightness.dim.primary);
      expect(dim.colorScheme.onSurfaceVariant, TextBrightness.dim.secondary);
    });
  });
}
