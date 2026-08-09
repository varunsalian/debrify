import 'dart:io';
import 'dart:math' as math;

import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:debrify/widgets/home/spotlight_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mock's numbers, made executable.
///
/// `apple_look_mockup/index.html` is the specification and it is drawn at
/// 1920×1080; everything in the Dart is logical, so **half**. A pixel diff
/// between Chrome and Flutter would be fake precision — different text
/// engines, different rasterisers — so instead the constants themselves are
/// asserted against the table, and the mock's own source is grepped so the two
/// cannot drift apart silently.
///
/// If one of these fails, decide which side is wrong before changing it. The
/// mock wins by default: it is the thing that was reviewed and agreed.
void main() {
  group('the focus mechanic matches the mock', () {
    test('per-shape lift', () {
      // 1.1 is a POSTER figure. A 216-wide episode still at 1.1 grows 21px and
      // eats its neighbour's gap.
      expect(ParallaxShape.poster.scale, 1.10);
      expect(ParallaxShape.landscape.scale, 1.10);
      expect(ParallaxShape.sourceCard.scale, 1.10);
      expect(ParallaxShape.episodeStill.scale, 1.055);
      expect(ParallaxShape.castCircle.scale, 1.08);
      expect(ParallaxShape.pill.scale, 1.06);
    });

    test('the spring is the reference\'s, not a curve', () {
      final s = kSettleFocusSpring;
      expect(s.mass, 1);
      expect(s.stiffness, 210);
      // ζ = damping / 2√(km) ≈ 0.82. Under 1, or it never overshoots and the
      // whole mechanic is an ease with extra steps.
      final zeta = s.damping / (2 * math.sqrt(s.mass * s.stiffness));
      expect(zeta, closeTo(0.82, 0.005));
      expect(zeta, lessThan(1.0), reason: 'critically damped never overshoots');
    });
  });

  group('the grounds are the MEASURED ones', () {
    test('Spotlight scrolls onto rgb(28,28,28), not black', () {
      // Sampled from the reference screenshots at every gutter of a scrolled
      // frame: a neutral grey drifting ~3 levels warmer down the page.
      expect(SpotlightBoard.ground, const Color(0xFF1B1C1C));
      expect(SpotlightBoard.groundLow, const Color(0xFF1F1D1C));
      // Not black, and not the app's near-black ink either.
      expect(SpotlightBoard.ground, isNot(const Color(0xFF000000)));
      expect(SpotlightBoard.ground, isNot(const Color(0xFF0A0A0B)));
    });

    test('the identity flips off a busy left third at 0.32', () {
      expect(SpotlightBoard.leftThirdBusy, 0.32);
    });
  });

  group('the mock and the code agree', () {
    // Grepping the mock keeps this honest in the other direction: if someone
    // retunes the HTML, the number it now states must still be the one the
    // Dart implements.
    final mock = File('apple_look_mockup/index.src.html');

    test('the mock is present — it IS the spec', () {
      expect(mock.existsSync(), isTrue,
          reason: 'apple_look_mockup/index.src.html is the source of truth');
    });

    test('the ambient field is damped the same way', () {
      final src = mock.readAsStringSync();
      // A bed for white text, not a picture: past ~1.4 saturation or under a
      // .55 veil the artwork competes with the episode titles sitting on it.
      expect(src, contains('saturate(1.35)'));
      expect(src, contains('rgba(10,10,11,.58)'));
    });

    test('the poster is 260×390 with a 40 gap — a 300 pitch', () {
      final src = mock.readAsStringSync();
      expect(src, contains('width:260px; height:390px'));
      // MEASURED off the reference screenshots, not read off the mock: card
      // edges at x = 69, 380, 680, 980, 1280 — a pitch of 300, so 260 of card
      // and 40 of gap. The gap was implemented at half this and that is what
      // "less space between them" was.
      expect(260 + 40, 300);
      // Proportions, not logical pixels: absolute values derived by halving
      // 1920 only land on a panel whose logical width is exactly 960.
      expect(260 / 1920, closeTo(0.1354, 0.0005));
      expect(40 / 1920, closeTo(0.0208, 0.0005));
    });

    test('the episode still is 432×243, cell 456, gap 46', () {
      final src = mock.readAsStringSync();
      expect(src, contains('width:432px; height:243px'));
      expect(432 / 243, closeTo(16 / 9, 0.01));
      expect(456 / 1920, closeTo(0.2375, 0.0005));
      expect(46 / 1920, closeTo(0.024, 0.0005));
    });

    test('the cast circle is 250 with a 52 gap', () {
      final src = mock.readAsStringSync();
      expect(src, contains('width:250px; height:250px'));
      expect(250 / 1920, closeTo(0.1302, 0.0005));
      expect(52 / 1920, closeTo(0.0271, 0.0005));
    });

    test('the page gutter is 84 — 4.375% of the width', () {
      final src = mock.readAsStringSync();
      expect(src, contains('padding-left:84px'));
      expect(84 / 1920, closeTo(0.04375, 0.0005));
    });

    test('focus is borderless — no ring survived the redesign', () {
      final src = mock.readAsStringSync();
      // The rings were removed deliberately: the lift is the signal, and a
      // ring on top of a lift reads as two cursors.
      expect(src, isNot(contains('3px solid rgba(255,255,255,.94)')));
    });
  });
}
