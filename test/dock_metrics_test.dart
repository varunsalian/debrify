import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase A gate for `design/plans/PLAYER_DOCK_STYLES_PLAN.md` §7.1.
///
/// The feature exists because the legacy dock's ~28lp targets fail Apple's
/// 44pt and Material's 48dp minimum on every device. A density system that can
/// itself produce a sub-44 target would be an own-goal — an earlier revision
/// of the plan did exactly that (`small` × compact gave 44 × 0.85 = 37.4), so
/// the floor is the first thing asserted here.
void main() {
  DockLayoutInput input(
    Size viewport, {
    PlayerDockSize size = PlayerDockSize.auto,
    double infoPanelH = 0,
    EdgeInsets safeArea = EdgeInsets.zero,
    double textScale = 1.0,
  }) => DockLayoutInput(
    viewport: viewport,
    safeArea: safeArea,
    arrangement: DockArrangement.forViewport(viewport),
    infoPanelH: infoPanelH,
    textScale: textScale,
    size: size,
  );

  group('arrangement selection', () {
    test('gates on height as well as width', () {
      // Two tiers cost two target-heights; a 360lp-tall viewport cannot afford
      // that at any density, however wide it is.
      expect(
        DockArrangement.forViewport(const Size(1920, 360)),
        DockArrangement.narrow,
      );
      expect(
        DockArrangement.forViewport(const Size(599, 1080)),
        DockArrangement.narrow,
      );
    });

    test('boundaries', () {
      expect(
        DockArrangement.forViewport(const Size(599, 479)),
        DockArrangement.narrow,
      );
      expect(
        DockArrangement.forViewport(const Size(600, 480)),
        DockArrangement.regular,
      );
      expect(
        DockArrangement.forViewport(const Size(1079, 800)),
        DockArrangement.regular,
      );
      expect(
        DockArrangement.forViewport(const Size(1080, 800)),
        DockArrangement.wide,
      );
    });
  });

  group('the 44lp floor', () {
    test('holds for every size x viewport that resolves', () {
      const viewports = [
        Size(320, 320),
        Size(360, 640),
        Size(599, 360),
        Size(599, 479),
        Size(600, 480),
        Size(800, 480),
        Size(1280, 800),
        Size(2560, 1440),
        Size(3840, 2160),
      ];
      const insets = [
        EdgeInsets.zero,
        EdgeInsets.only(top: 48, bottom: 34),
      ];
      for (final viewport in viewports) {
        for (final size in PlayerDockSize.values) {
          for (final safeArea in insets) {
            for (final panel in const [0.0, 80.0, 100.0]) {
              final metrics = DockMetrics.compute(
                input(
                  viewport,
                  size: size,
                  infoPanelH: panel,
                  safeArea: safeArea,
                ),
              );
              // Null is a legitimate outcome — the caller renders classic.
              if (metrics == null) continue;
              expect(
                metrics.target,
                greaterThanOrEqualTo(DockLayoutInput.minTarget),
                reason: '$viewport / ${size.name} / panel $panel / $safeArea',
              );
            }
          }
        }
      }
    });

    test('a shrinking size override cannot breach it', () {
      final small = DockMetrics.compute(
        input(const Size(360, 640), size: PlayerDockSize.small),
      );
      expect(small!.target, DockLayoutInput.minTarget);
    });
  });

  group('scale resolution', () {
    test('auto grows with the viewport, up to the cap', () {
      final phone = DockMetrics.compute(input(const Size(360, 640)))!;
      final desktop = DockMetrics.compute(input(const Size(2560, 1440)))!;
      expect(phone.k, 1.0);
      expect(desktop.k, greaterThan(phone.k));
      expect(desktop.k, lessThanOrEqualTo(DockLayoutInput.maxK));
    });

    test('auto and medium are genuinely different', () {
      // An earlier revision made both 1.0 against the same viewport-derived k,
      // which made the setting a lie.
      const big = Size(2560, 1440);
      final auto = DockMetrics.compute(input(big))!;
      final medium = DockMetrics.compute(
        input(big, size: PlayerDockSize.medium),
      )!;
      expect(medium.k, 1.25);
      expect(auto.k, isNot(medium.k));
    });

    test('a pinned size is an upper bound that degrades, never a floor', () {
      // Cramped: large asks 1.50 and cannot have it.
      final cramped = DockMetrics.compute(
        input(
          const Size(900, 300),
          size: PlayerDockSize.large,
          infoPanelH: 100,
        ),
      );
      if (cramped != null) {
        expect(cramped.k, lessThanOrEqualTo(1.50));
      }
      // Roomy: large gets exactly what it asked for, and does not grow beyond.
      final roomy = DockMetrics.compute(
        input(const Size(2560, 1440), size: PlayerDockSize.large),
      )!;
      expect(roomy.k, 1.50);
    });
  });

  group('the vertical budget', () {
    test('the plan\'s worked worst case resolves as documented', () {
      // 599x360, large, full-EPG panel, zero insets -> narrow, one row.
      // reserved = 72 + 100 + 56 + 38 = 266; budget = 94; fitK = 2.14.
      final metrics = DockMetrics.compute(
        input(
          const Size(599, 360),
          size: PlayerDockSize.large,
          infoPanelH: 100,
        ),
      );
      expect(metrics, isNotNull);
      expect(metrics!.k, 1.50);
      expect(metrics.target, 66.0);
    });

    test('returns null rather than overflowing when a row cannot fit', () {
      // 320x240 with a full-EPG panel: reserved alone exceeds the viewport.
      // Classic does not fit here either - a pre-existing, configuration-
      // dependent overflow this feature declines to make worse.
      expect(
        DockMetrics.compute(input(const Size(320, 240), infoPanelH: 100)),
        isNull,
      );
    });

    test('insets and panel height both reduce the budget', () {
      const viewport = Size(800, 480);
      final bare = DockMetrics.compute(input(viewport))!;
      final withPanel = DockMetrics.compute(
        input(viewport, infoPanelH: 100),
      );
      final withBoth = DockMetrics.compute(
        input(
          viewport,
          infoPanelH: 100,
          safeArea: const EdgeInsets.only(top: 48, bottom: 34),
        ),
      );
      for (final tighter in [withPanel, withBoth]) {
        if (tighter != null) expect(tighter.k, lessThanOrEqualTo(bare.k));
      }
    });
  });

  group('derived metrics', () {
    test('label is a base size, never pre-multiplied by the text scaler', () {
      // Labels ride the platform's own clamped scaler (main.dart caps at 1.3),
      // and Android's curve is non-linear. Scaling here too would double-apply.
      const viewport = Size(1280, 800);
      final plain = DockMetrics.compute(input(viewport))!;
      final scaled = DockMetrics.compute(input(viewport, textScale: 1.3))!;
      expect(scaled.label, plain.label);
      expect(plain.label, 12 * plain.k);
    });

    test('every metric scales from its base', () {
      final m = DockMetrics.compute(
        input(const Size(2560, 1440), size: PlayerDockSize.large),
      )!;
      expect(m.icon, 20 * 1.5);
      expect(m.padX, 10 * 1.5);
      expect(m.padY, 8 * 1.5);
      expect(m.gap, 8 * 1.5);
      expect(m.radius, 10 * 1.5);
      expect(m.trackHeight, 4 * 1.5);
      expect(m.knob, 12 * 1.5);
    });
  });

  group('preference parsing', () {
    test('unknown and null coerce to the defaults', () {
      for (final raw in [null, '', 'nonsense']) {
        expect(PlayerDockStyle.fromPref(raw), PlayerDockStyle.classic);
        expect(PlayerDockPalette.fromPref(raw), PlayerDockPalette.ultraviolet);
        expect(PlayerDockSize.fromPref(raw), PlayerDockSize.auto);
      }
    });

    test('round-trips', () {
      for (final v in PlayerDockStyle.values) {
        expect(PlayerDockStyle.fromPref(v.prefValue), v);
      }
      for (final v in PlayerDockPalette.values) {
        expect(PlayerDockPalette.fromPref(v.prefValue), v);
      }
      for (final v in PlayerDockSize.values) {
        expect(PlayerDockSize.fromPref(v.prefValue), v);
      }
    });

    test('classic is the default and is not styled', () {
      expect(PlayerDockStyle.fromPref(null).isStyled, isFalse);
      for (final s in PlayerDockStyle.values.where(
        (s) => s != PlayerDockStyle.classic,
      )) {
        expect(s.isStyled, isTrue, reason: s.name);
      }
    });

    test('the pre-selectable `two_tier` value still resolves to Adaptive', () {
      // Installs that chose the styled dock before the arrangements became
      // selectable must keep it, not silently drop back to Classic.
      expect(PlayerDockStyle.fromPref('two_tier'), PlayerDockStyle.auto);
      expect(PlayerDockStyle.fromPref('two_tier').isStyled, isTrue);
    });

    test('only Adaptive defers to the viewport', () {
      expect(PlayerDockStyle.auto.forcedArrangement, isNull);
      expect(PlayerDockStyle.classic.forcedArrangement, isNull);
      expect(
        PlayerDockStyle.compact.forcedArrangement,
        DockArrangement.narrow,
      );
      expect(PlayerDockStyle.tiers.forcedArrangement, DockArrangement.regular);
      expect(PlayerDockStyle.cinema.forcedArrangement, DockArrangement.wide);
    });
  });

  group('palettes', () {
    test('all four resolve', () {
      for (final p in PlayerDockPalette.values) {
        expect(DockPalettes.of(p), isNotNull);
      }
    });

    test('two palettes need dark ink on the primary, not one', () {
      // The plan long claimed aurum was the only one. It is not: ice's hot end
      // (#7BF1FF) is light enough to need dark ink too. A real branch, not a
      // token swap - hardcoding white ships an invisible glyph on both.
      final dark = PlayerDockPalette.values.where(
        (p) => DockPalettes.of(p).onPrimary != const Color(0xFFFFFFFF),
      );
      expect(dark, [PlayerDockPalette.aurum, PlayerDockPalette.ice]);
      expect(DockPalettes.of(PlayerDockPalette.aurum).onPrimary.alpha, 0xFF);
    });

    test('every token is fully opaque or deliberately pre-multiplied', () {
      // House rule: no Opacity widgets over video - alpha is baked in.
      for (final p in PlayerDockPalette.values) {
        final t = DockPalettes.of(p);
        expect(t.hot.alpha, 0xFF);
        expect(t.deep.alpha, 0xFF);
        expect(t.onPrimary.alpha, 0xFF);
        expect(t.scrim.alpha, greaterThan(0xD0));
      }
    });
  });
}
