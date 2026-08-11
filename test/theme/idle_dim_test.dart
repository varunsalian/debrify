import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/theme/app_ambience.dart';
import 'package:debrify/theme/app_surfaces.dart';
import 'package:debrify/theme/app_theme_controller.dart';
import 'package:debrify/theme/idle_dim.dart';

/// The transition table from plan §3.7, as tests.
///
/// The one that is easy to get wrong is "restarts from zero, never resumes":
/// resuming an elapsed timer means a trailer that ends at 29 seconds dims the
/// room one second later, which reads as a bug even though it is arithmetic.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IdleDim.instance.uninstall();
    AppSurfaceState.instance
      ..reset()
      ..publishBootstrap(false);
    await AppThemeController.instance.select('legacy');
    IdleDim.instance.install();
  });

  tearDown(() async {
    IdleDim.instance.uninstall();
    AppSurfaceState.instance.reset();
    await AppThemeController.instance.select('legacy');
  });

  test('legacy never arms — no policy, no timer, no dim', () {
    IdleDim.instance.noteInput();
    expect(IdleDim.instance.debugArmed, isFalse);
    expect(IdleDim.instance.idleDim.value, 0);
  });

  test('the effective dim is the max of its two producers', () {
    IdleDim.instance.trailerDim.value = 0.4;
    expect(IdleDim.instance.effective.value, 0.4);
    IdleDim.instance.idleDim.value = 0.7;
    expect(IdleDim.instance.effective.value, 0.7);
    // The case a per-screen opacity gets wrong: the smaller producer falling
    // away must not pull the room back up.
    IdleDim.instance.trailerDim.value = 0;
    expect(IdleDim.instance.effective.value, 0.7);
  });

  test('a producer that never suspended cannot release someone else\'s hold',
      () {
    final trailer = Object();
    final player = Object();
    IdleDim.instance.suspend(trailer);
    IdleDim.instance.suspend(player);
    // Disposal is idempotent per owner — a producer that resets twice must not
    // decrement a hold it does not own.
    IdleDim.instance.resume(player);
    IdleDim.instance.resume(player);
    expect(IdleDim.instance.debugHolds, contains(trailer));
    IdleDim.instance.resume(Object());
    expect(IdleDim.instance.debugHolds, hasLength(1));
  });

  test('a frozen surface takes a hold, and unfreezing gives it back', () {
    expect(IdleDim.instance.debugHolds, isEmpty);
    AppSurfaceState.instance.publishBootstrap(true);
    expect(IdleDim.instance.debugHolds, hasLength(1));
    AppSurfaceState.instance.publishBootstrap(false);
    expect(IdleDim.instance.debugHolds, isEmpty);
  });

  group('with a policy', () {
    setUp(() async {
      // Midnight Cinema is the theater look. Its policy is TV-only, so on this
      // host `policyFor` returns none and the timer never arms — which is the
      // point of the next test.
      await AppThemeController.instance.select('reel');
    });

    test('v1 is TV only: a phone or desktop never dims itself', () {
      IdleDim.instance.noteInput();
      expect(IdleDim.instance.debugArmed, isFalse,
          reason: 'a desktop window that dims itself is a bug report');
    });

    test('the look still carries the policy for the platform that has it', () {
      final idle = AppThemeController.instance.theme.idle;
      expect(idle.policy, IdlePolicy.theater);
      expect(idle.policyFor(true), IdlePolicy.theater);
      expect(idle.policyFor(false), IdlePolicy.none);
      expect(idle.depth, greaterThan(0));
    });

    test('changing theme clears a dim that the new look cannot explain',
        () async {
      IdleDim.instance.idleDim.value = 0.85;
      await AppThemeController.instance.select('legacy');
      expect(IdleDim.instance.idleDim.value, 0);
      expect(IdleDim.instance.effective.value, 0);
    });
  });

  group('IdleChrome', () {
    testWidgets('is its child and nothing else under a no-idle look',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: IdleChrome(child: Text('rail'))),
      );
      // No listenable, no animation, no wrapper — the whole point of the
      // legacy pin is that a look with no opinion costs nothing.
      expect(find.byType(ValueListenableBuilder<double>), findsNothing);
      expect(find.byType(AnimatedOpacity), findsNothing);
      expect(find.text('rail'), findsOneWidget);
    });
  });
}
