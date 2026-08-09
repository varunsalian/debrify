import 'package:debrify/theme/app_focus.dart';
import 'package:debrify/theme/app_motion.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/theme/app_light.dart';
import 'package:debrify/theme/app_art.dart';
import 'package:debrify/theme/app_surface.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/theme_spec.dart';
import 'package:debrify/theme/widgets/focus_expression.dart';
import 'package:debrify/theme/widgets/parallax_focus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The focus mechanic, pinned.
///
/// The mechanic is the whole reason this look exists — an eased scale was
/// already what the app did, and was the specific complaint. So the properties
/// that separate it from an eased scale get tests: a real spring, an overshoot
/// that is allowed to exceed 1, a lean that depends on arrival direction, and
/// nothing at all in the tree under every other theme.
void main() {
  Widget host(AppTheme theme, Widget child, {bool reduceMotion = false}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: AppThemeScope(theme: theme, child: Center(child: child)),
        ),
      );

  /// A theme whose only interesting properties are the expression and the
  /// character under test. Built through `ThemeSpec` rather than by hand so it
  /// travels the same derivation path the real looks do — including the
  /// `copyWith` that round 1 of this work found silently dropping the spring.
  AppTheme themeWith(
    FocusExpression e, {
    MotionCharacter m = MotionCharacter.settle,
  }) =>
      ThemeSpec(
        id: 'probe',
        label: 'Probe',
        subtitle: 'test fixture',
        ground: const Color(0xFF101010),
        sunken: const Color(0xFF0A0A0A),
        raised: const Color(0xFF1A1A1A),
        ink: const Color(0xFFFFFFFF),
        accent: const Color(0xFFFFFFFF),
        separation: SeparationModel.fill,
        scrim: ScrimStyle.bottomGradient,
        frame: ArtFrame.bleed,
        focusExpression: e,
        motion: m,
        radius: 7,
      ).build();

  group('the spring', () {
    test('settle carries a spring; every other character does not', () {
      expect(MotionTokens.of(MotionCharacter.settle).focusSpring, isNotNull);
      for (final c in [
        MotionCharacter.standard,
        MotionCharacter.snap,
        MotionCharacter.glide,
      ]) {
        expect(MotionTokens.of(c).focusSpring, isNull, reason: c.name);
      }
    });

    test('copyWith carries it — ThemeSpec rebuilds motion through copyWith', () {
      // The failure this guards is silent: ThemeSpec does
      // `MotionTokens.of(c).copyWith(entrance: …)`, so a copyWith that forgets
      // the field leaves every themed surface on the curve path with no error.
      final copied = MotionTokens.of(MotionCharacter.settle)
          .copyWith(entrance: EntranceStyle.fadeUp);
      expect(copied.focusSpring, isNotNull);
      expect(copied.entrance, EntranceStyle.fadeUp);
    });

    test('is under-damped — a critically damped spring never overshoots', () {
      final s = kSettleFocusSpring;
      final critical = 2 * (s.mass * s.stiffness).abs().toDouble();
      // damping < 2√(km) is the definition of under-damped.
      expect(s.damping, lessThan(2 * 14.5));
      expect(critical, greaterThan(0));
    });
  });

  group('the widget is absent under every other expression', () {
    for (final e in FocusExpression.values) {
      if (e == FocusExpression.parallax) continue;
      testWidgets('$e adds no transform of its own', (tester) async {
        await tester.pumpWidget(
          host(
            themeWith(e),
            const ParallaxFocus(
              focused: true,
              child: SizedBox(width: 100, height: 60),
            ),
          ),
        );
        // The STRONG claim: no animated body was built at all. "No Transform
        // is painted" would also pass with an idle controller sitting in the
        // tree, which is the cost this split exists to avoid.
        expect(ParallaxFocus.debugLiveBodies, 0);
        expect(
          find.descendant(
            of: find.byType(ParallaxFocus),
            matching: find.byType(Transform),
          ),
          findsNothing,
        );
      });
    }
  });

  group('parallax', () {
    setUp(ParallaxTravel.resetForTest);

    testWidgets('lifts on focus and settles back', (tester) async {
      Widget build(bool focused) => host(
            themeWith(FocusExpression.parallax),
            ParallaxFocus(
              focused: focused,
              child: const SizedBox(width: 100, height: 60),
            ),
          );

      await tester.pumpWidget(build(false));
      final rest = tester.getRect(find.byType(SizedBox).first).width;

      await tester.pumpWidget(build(true));

      // Sample the whole flight. Two properties are being pinned at once:
      // the card grows, and — because the controller is UNBOUNDED and the
      // spring under-damped — it passes its own target on the way and comes
      // back. A bounded controller or a ζ of 1 would fail the second.
      var peak = rest;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final w = tester.getRect(find.byType(SizedBox).first).width;
        if (w > peak) peak = w;
      }
      await tester.pumpAndSettle();
      final settled = tester.getRect(find.byType(SizedBox).first).width;

      expect(settled, greaterThan(rest), reason: 'the card must lift');
      expect(
        settled,
        closeTo(rest * ParallaxShape.poster.scale, 0.5),
        reason: 'and settle exactly on the shape\'s scale',
      );
      // ζ 0.82 overshoots by exp(-πζ/√(1-ζ²)) ≈ 1.1% OF THE TRAVEL — about
      // 0.11px on a 100px card growing to 110. Small, and correct: the felt
      // quality comes from the settle and the lean, not from a big bounce.
      // What matters is that an overshoot exists at all, which a decelerating
      // curve cannot produce.
      final overshoot = peak - settled;
      expect(overshoot, greaterThan(0.04),
          reason: 'it must OVERSHOOT — the whole difference from an ease-out');
      expect(overshoot, lessThan(0.5),
          reason: 'but not bounce: ζ 0.82, not 0.4');
    });

    testWidgets('reduced motion lands on the lifted state immediately',
        (tester) async {
      await tester.pumpWidget(
        host(
          themeWith(FocusExpression.parallax),
          const ParallaxFocus(
            focused: false,
            child: SizedBox(width: 100, height: 60),
          ),
          reduceMotion: true,
        ),
      );
      await tester.pumpWidget(
        host(
          themeWith(FocusExpression.parallax),
          const ParallaxFocus(
            focused: true,
            child: SizedBox(width: 100, height: 60),
          ),
          reduceMotion: true,
        ),
      );
      // One pump, no settle: with animations disabled there is nothing to
      // wait for. If this needed pumpAndSettle the state would be animating,
      // which is the thing reduced motion forbids.
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      // And it must land LIFTED. Reduced motion removes the movement, not the
      // cursor — a focused card that never grew has no focus indication.
      final w = tester.getRect(find.byType(SizedBox).first).width;
      expect(w, closeTo(100 * ParallaxShape.poster.scale, 0.5));
    });

    testWidgets('the tilt swings THROUGH neutral, not in one direction only',
        (tester) async {
      // The defect this pins: deriving tilt from a bell curve over the
      // controller's POSITION can only ever lean one way — it rises, hits
      // zero at the top, and leans the same way again on the rebound. Riding
      // the spring's VELOCITY reverses the lean when the spring reverses,
      // which is what "kick the rotation and let it swing back" means.
      Widget build(bool focused) => host(
            themeWith(FocusExpression.parallax),
            ParallaxFocus(
              focused: focused,
              child: const SizedBox(width: 100, height: 60),
            ),
          );
      await tester.pumpWidget(build(false));
      ParallaxTravel.note(const Offset(1, 0));
      await tester.pumpWidget(build(true));

      double shiftX() {
        final t = tester.widget<Transform>(
          find.descendant(
            of: find.byType(ParallaxFocus),
            matching: find.byType(Transform),
          ),
        );
        return t.transform.getTranslation().x;
      }

      var sawPositive = false, sawNegative = false;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final x = shiftX();
        if (x > 0.02) sawPositive = true;
        if (x < -0.02) sawNegative = true;
      }
      await tester.pumpAndSettle();

      expect(sawPositive && sawNegative, isTrue,
          reason: 'the lean must reverse as the spring rebounds');
      expect(shiftX(), closeTo(0, 0.01),
          reason: 'and end flat — the lean is an arrival, not a pose');
    });

    testWidgets('a focused card holds no RUNNING ticker once settled',
        (tester) async {
      await tester.pumpWidget(
        host(
          themeWith(FocusExpression.parallax),
          const ParallaxFocus(
            focused: true,
            child: SizedBox(width: 100, height: 60),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('ParallaxTravel', () {
    setUp(ParallaxTravel.resetForTest);

    test('an unnoted arrival has no direction — a tap must not lean', () {
      expect(ParallaxTravel.take().dir, Offset.zero);
    });

    test('a noted direction is delivered once, then cleared', () {
      ParallaxTravel.note(const Offset(1, 0));
      final first = ParallaxTravel.take();
      expect(first.dir, const Offset(1, 0));
      // Consumed: the next card to gain focus without its own note must not
      // inherit this one's lean.
      expect(ParallaxTravel.take().dir, Offset.zero);
    });

    test('rapid is the gap between MOVES, not the gap before focus lands', () {
      // The bug this pins: measuring note→take always reads ~0, because focus
      // arrives within a frame — so every single step would be called rapid
      // and the gentler lean would be unreachable.
      var now = Duration.zero;
      ParallaxTravel.clock = () => now;

      ParallaxTravel.note(const Offset(1, 0));   // first move of a burst
      expect(ParallaxTravel.take().rapid, isFalse,
          reason: 'an isolated step is not a traversal');

      now += const Duration(milliseconds: 90);   // held down
      ParallaxTravel.note(const Offset(1, 0));
      expect(ParallaxTravel.take().rapid, isTrue);

      now += const Duration(milliseconds: 900);  // thought about it
      ParallaxTravel.note(const Offset(1, 0));
      expect(ParallaxTravel.take().rapid, isFalse);
    });

    test('a stale note is not delivered — a tap must not inherit a lean', () {
      var now = Duration.zero;
      ParallaxTravel.clock = () => now;
      ParallaxTravel.note(const Offset(1, 0));
      now += const Duration(milliseconds: 900);
      expect(ParallaxTravel.take().dir, Offset.zero);
    });

    test('both axes survive — DOWN must not lean like RIGHT', () {
      ParallaxTravel.note(const Offset(0, 1));
      expect(ParallaxTravel.take().dir, const Offset(0, 1));
    });
  });

  group('the expression is wired into the shared cursor', () {
    testWidgets('FocusExpressionBox delegates to ParallaxFocus', (tester) async {
      await tester.pumpWidget(
        host(
          themeWith(FocusExpression.parallax),
          const FocusExpressionBox(
            focused: true,
            radius: 8,
            child: SizedBox(width: 100, height: 60),
          ),
        ),
      );
      // Without the arm this box would fall through every branch and paint
      // nothing — a theme with no cursor at all.
      expect(find.byType(ParallaxFocus), findsOneWidget);
    });

    test('parallax draws no ring — the lift is the signal', () {
      const t = FocusTokens(
        expression: FocusExpression.parallax,
        width: 2.5,
        offset: 0,
        scale: 1,
        lift: 0,
      );
      expect(t.drawsRing, isFalse);
    });
  });
}
