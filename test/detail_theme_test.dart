import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:debrify/widgets/detail/theme/detail_themes.dart';
import 'package:debrify/widgets/home/home_theme.dart';

void main() {
  _literalGuard();

  group('registry', () {
    test('twenty themes, no duplicate ids', () {
      expect(DetailThemes.all.length, 20);
      final ids = DetailThemes.all.map((t) => t.id).toSet();
      expect(ids.length, 20, reason: 'duplicate theme id');
    });

    test('signal is first, so it is the picker default', () {
      expect(DetailThemes.all.first.id, 'signal');
    });

    test('byId falls back to signal for anything unknown', () {
      expect(DetailThemes.byId('nonsense').id, 'signal');
      expect(DetailThemes.byId('').id, 'signal');
      for (final t in DetailThemes.all) {
        expect(identical(DetailThemes.byId(t.id), t), isTrue);
      }
    });

    test('every theme has a label and a subtitle', () {
      for (final t in DetailThemes.all) {
        expect(t.label, isNotEmpty, reason: t.id);
        expect(t.subtitle, isNotEmpty, reason: t.id);
      }
    });
  });

  // The whole refactor is only safe if Signal is exactly what ships today.
  // These are the values from plan §3.2a, read out of the pre-refactor code.
  group('signal reproduces today exactly', () {
    const s = DetailThemes.signal;

    test('grounds', () {
      expect(s.ground, const Color(0xFF0B0B0E));
      expect(s.pane, const Color(0xFF0E0B14));
    });

    test('state, callout and award are the one gold today', () {
      expect(s.state, const Color(0xFFF5B942));
      expect(s.callout, const Color(0xFFF5B942));
      expect(s.award, const Color(0xFFF5B942));
    });

    test('rating is IMDb yellow, NOT the state gold', () {
      expect(s.rating, const Color(0xFFF5C518));
      expect(s.rating, isNot(s.state));
    });

    test('callout foreground is the UP NEXT ink', () {
      expect(s.calloutText, const Color(0xFF2A1E02));
    });

    test('focus matches HomeTheme.focusGold, 2.5px, in bounds', () {
      expect(s.focus, HomeTheme.focusGold);
      expect(s.focusWidth, 2.5);
      expect(s.focusOffset, 0, reason: 'today draws an in-bounds ring');
    });

    test('keeps the poster-extracted accent and its wash', () {
      expect(s.useArtworkAccent, isTrue);
      expect(s.washOpacity, 0.16);
    });

    test('primary button is the white pill', () {
      expect(s.btnFill, const Color(0xFFF6F5F0));
      expect(s.btnText, const Color(0xFF0D0D10));
    });

    test('is the only theme using the artwork accent', () {
      final artwork = DetailThemes.all.where((t) => t.useArtworkAccent);
      expect(artwork.map((t) => t.id), ['signal']);
    });
  });

  group('rules a theme cannot break', () {
    test('focus width has a TV floor', () {
      // Vault and Cinemascope both ask for 1px, which vanishes at three metres.
      for (final t in [DetailThemes.vault, DetailThemes.cinemascope]) {
        expect(t.focusWidth, lessThan(2.5), reason: '${t.id} setup');
        expect(t.focusWidthFor(true), 2.5, reason: '${t.id} on TV');
        expect(t.focusWidthFor(false), t.focusWidth, reason: '${t.id} off TV');
      }
    });

    test('every theme is visible on TV', () {
      for (final t in DetailThemes.all) {
        expect(t.focusWidthFor(true), greaterThanOrEqualTo(2.5), reason: t.id);
      }
    });

    test('grain is off on TV — a blend layer is a per-frame saveLayer', () {
      for (final t in DetailThemes.all) {
        expect(t.grainFor(true), 0, reason: t.id);
      }
      expect(DetailThemes.sepia.grainFor(false), greaterThan(0));
      expect(DetailThemes.cinemascope.grainFor(false), greaterThan(0));
    });

    test('blur shadows are dropped on TV, hard ones survive', () {
      // Aurora 40px, Deep Field 30px, Frost 44px all re-raster on focus moves.
      for (final t in [
        DetailThemes.aurora,
        DetailThemes.deepField,
        DetailThemes.frost,
      ]) {
        expect(t.shadow, isNotEmpty, reason: '${t.id} setup');
        expect(t.shadowFor(true), isEmpty, reason: '${t.id} on TV');
        expect(t.shadowFor(false), t.shadow, reason: '${t.id} off TV');
      }
      // Concrete's offset block has no blur, so it costs nothing and stays.
      expect(DetailThemes.concrete.shadowFor(true), isNotEmpty);
    });
  });

  group('token coherence', () {
    test('only Broadsheet and Concrete claim a light ground', () {
      final light = DetailThemes.all
          .where((t) => t.lightGround)
          .map((t) => t.id);
      expect(light, unorderedEquals(['broadsheet', 'concrete']));
    });

    test('light themes have dark text and dark themes light text', () {
      for (final t in DetailThemes.all) {
        final groundLum = t.ground.computeLuminance();
        final txLum = t.tx.computeLuminance();
        expect(
          (groundLum - txLum).abs(),
          greaterThan(0.35),
          reason: '${t.id} has too little text/ground contrast',
        );
      }
    });

    test('a gradient is never the only carrier of state', () {
      // Spectrum's duotone rides the progress bar; ticks and text stay flat, so
      // small type never becomes an unreadable gradient.
      for (final t in DetailThemes.all) {
        if (t.stateGradient != null) {
          expect(t.state, isNotNull, reason: '${t.id} needs a flat state too');
        }
      }
    });

    test('font roles resolve to a family or the platform default', () {
      expect(DetailFontRole.sans.family, isNull);
      expect(DetailFontRole.serif.family, 'serif');
      expect(DetailFontRole.mono.family, 'monospace');
      expect(DetailFontRole.sans.fallback, isNull);
      expect(DetailFontRole.serif.fallback, isNotEmpty);
    });

    test('display sizes stay inside a sane band', () {
      // §2a: type size moves focus rectangles, so a runaway value is a
      // traversal bug, not just an ugly one.
      for (final t in DetailThemes.all) {
        expect(t.displaySize, inInclusiveRange(16, 34), reason: t.id);
      }
    });
  });

  group('scope', () {
    testWidgets('of() returns the provided theme', (tester) async {
      late DetailTheme seen;
      await tester.pumpWidget(
        DetailThemeScope(
          theme: DetailThemes.noir,
          child: Builder(
            builder: (context) {
              seen = DetailThemeScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(identical(seen, DetailThemes.noir), isTrue);
    });

    testWidgets('maybeOf falls back to signal outside a scope', (tester) async {
      late DetailTheme seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = DetailThemeScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      );
      expect(identical(seen, DetailThemes.signal), isTrue);
    });

    testWidgets('updateShouldNotify fires only on a real change', (
      tester,
    ) async {
      // The probe must be a CONST widget: a Builder with a fresh closure is a
      // new widget every pump, so it rebuilds regardless of the inherited
      // dependency and the test would pass whatever updateShouldNotify did.
      _ThemeProbe.builds = 0;

      Widget tree(DetailTheme t) =>
          DetailThemeScope(theme: t, child: const _ThemeProbe());

      await tester.pumpWidget(tree(DetailThemes.signal));
      expect(_ThemeProbe.builds, 1);

      // Same const singleton — identical, so no dependent rebuild.
      await tester.pumpWidget(tree(DetailThemes.signal));
      expect(_ThemeProbe.builds, 1);

      await tester.pumpWidget(tree(DetailThemes.vault));
      expect(_ThemeProbe.builds, 2);
    });
  });
}

/// Const so the element is reused across pumps; only an inherited-dependency
/// change can rebuild it.
class _ThemeProbe extends StatelessWidget {
  static int builds = 0;
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) {
    DetailThemeScope.of(context);
    builds++;
    return const SizedBox();
  }
}

/// The literal guard.
///
/// The biggest risk in the theme migration was never a wrong token — it was a
/// colour that never got routed through one at all, which renders white-on-
/// paper under Broadsheet and Concrete. A golden would only catch that if the
/// missed literal happened to land in a golden'd region; reading the source
/// catches all of them, and keeps catching them for whoever adds a widget next.
void _literalGuard() {
  group('no raw colour literals survive in the themed files', () {
    // Deliberate exceptions, each a semantic constant rather than a style
    // choice: a third party's logo, a scrim over a PHOTOGRAPH (not over a
    // themed surface), and the parents-guide severity scale, where green→red
    // has to mean the same thing in every theme.
    final allowed = RegExp(
      r'0xFFF5C518' // IMDb badge
      r'|0xFF4ADE80|0xFFFBBF24|0xFFFB923C|0xFFEF4444|0xFF8A8A8A' // severity
      r'|Colors\.black\.withValues' // scrim over artwork
      r'|color: Colors\.black,', // IMDb badge foreground
    );
    final literal = RegExp(
      r'Colors\.(white|black)\w*|Color\(0x[0-9A-Fa-f]{8}\)',
    );

    const files = [
      'lib/widgets/detail/detail_style.dart',
      'lib/widgets/detail/detail_identity.dart',
      'lib/widgets/detail/detail_episode_cells.dart',
      'lib/widgets/detail/detail_layout_marquee.dart',
      'lib/widgets/detail/detail_layout_dossier.dart',
      'lib/widgets/detail/detail_layout_stage.dart',
      'lib/widgets/detail/detail_layout_console.dart',
    ];

    for (final path in files) {
      test(path.split('/').last, () {
        final file = File(path);
        if (!file.existsSync()) return; // not run from the repo root
        final offenders = <String>[];
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (!literal.hasMatch(line)) continue;
          if (allowed.hasMatch(line)) continue;
          offenders.add('  ${i + 1}: ${line.trim()}');
        }
        expect(
          offenders,
          isEmpty,
          reason:
              'raw colour literals must go through a DetailTheme token, or '
              'they render white-on-white under Broadsheet and Concrete:\n'
              '${offenders.join('\n')}',
        );
      });
    }
  });

  group('Signal is pinned to the look that shipped', () {
    // Signal is not a theme anyone chose — it is the CURRENT page. Every value
    // here was read off the pre-theme source, so a drift shows up as a failing
    // test rather than as a user noticing the page got dimmer.
    const t = DetailThemes.signal;

    test('palette', () {
      expect(t.ground, const Color(0xFF0B0B0E));
      expect(t.pane, const Color(0xFF0E0B14));
      expect(t.railBg, const Color(0xFF0A0A0D));
      expect(t.panel, const Color(0x12FFFFFF));
      expect(t.hair, const Color(0x1CFFFFFF));
      // Pure white at the shipped alphas, NOT a warm off-white.
      expect(t.tx, const Color(0xFFFFFFFF));
      expect(t.tx2, const Color(0xA3FFFFFF));
      expect(t.tx3, const Color(0x66FFFFFF));
      expect(t.placeholder, const Color(0xFF1A1622));
    });

    test('geometry', () {
      expect(t.radius, 10);
      expect(t.radiusSm, 4);
      expect(t.radiusImg, 8);
      expect(t.radiusBtn, 999);
      // Artwork radii are scaled off 8, so Signal's are exactly their sites'.
      expect(t.imgRadius(9), BorderRadius.circular(9));
      expect(t.imgRadius(13), BorderRadius.circular(13));
    });

    test('type is unstyled — shipped Signal has no serif and no monospace', () {
      expect(t.displayFont, DetailFontRole.sans);
      expect(t.bodyFont, DetailFontRole.sans);
      expect(t.dataFont, DetailFontRole.sans);
      expect(t.displayUpper, isFalse);
      expect(t.displayScale, 1.0);
      // Null means "the site decides", so no site's weight is overridden.
      expect(t.displayWeight, isNull);
      expect(t.displayTracking, isNull);
      final title = t.titleStyle(
        size: 20,
        weight: FontWeight.w700,
        tracking: -0.4,
      );
      expect(title.fontSize, 20);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.letterSpacing, -0.4);
      expect(title.fontFamily, isNull);
    });

    test('no texture, no offset ring', () {
      expect(t.grain, 0);
      expect(t.grid, isFalse);
      expect(t.focusOffset, 0);
      expect(t.paneWash, isNull);
      expect(t.railWash, isNull);
      expect(t.idWash, isNull);
      expect(t.dividerGradient, isNull);
    });
  });

  group('the cursor is visible under every theme', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    for (final t in DetailThemes.all) {
      test('${t.id} · ring contrasts with the primary button it sits on', () {
        // Mirrors DetailPrimaryButton exactly: a gradient theme's ring sits on
        // the gradient's last stop, not on btnFill. Testing focusOn against a
        // surface the button never passes is how Spectrum's cyan-on-cyan ring
        // passed this check while being invisible on screen.
        final surface = t.btnGradient == null
            ? t.btnFill
            : t.btnGradient!.colors.last;
        expect(
          contrast(t.focusOn(surface), surface),
          greaterThanOrEqualTo(1.6),
          reason: '${t.id}: cursor invisible on its own primary button',
        );
      });

      test('${t.id} · ring contrasts with the page ground', () {
        expect(
          contrast(t.focus, t.ground),
          greaterThanOrEqualTo(1.6),
          reason: '${t.id}: cursor invisible against the page',
        );
      });

      test('${t.id} · body text contrasts with the page ground', () {
        // A light theme that kept an inherited white would fail here.
        expect(
          contrast(t.tx, t.ground),
          greaterThanOrEqualTo(4.5),
          reason: '${t.id}: primary text unreadable on its own ground',
        );
        expect(contrast(t.tx2, t.ground), greaterThanOrEqualTo(2.5));
      });

      test('${t.id} · button label contrasts with the button fill', () {
        expect(
          contrast(t.btnText, t.btnFill),
          greaterThanOrEqualTo(3.0),
          reason: '${t.id}: primary button label unreadable',
        );
      });
    }
  });
}
