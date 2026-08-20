import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_pin_screen.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20);
  final profile = UserProfile(
    id: 'profile-1',
    name: 'Varun',
    role: UserProfileRole.admin,
    policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    authorizationRevision: 1,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: false,
    hasPin: true,
    lockOnResume: false,
    createdAt: now,
    updatedAt: now,
  );

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    required Future<ProfilePinVerification> Function(String) onSubmit,
    bool television = false,
  }) async {
    PlatformUtil.debugSetAndroidTvCached(television);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePinScreen(
          profile: profile,
          onSubmit: onSubmit,
          onCancel: () {},
          onRecovery: (_) async => ProfileRecoveryResult.invalid,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('phone layout enters and submits a PIN without overflow', (
    tester,
  ) async {
    String? submitted;
    await pump(
      tester,
      size: const Size(390, 844),
      onSubmit: (pin) async {
        submitted = pin;
        return const ProfilePinVerification(ProfilePinResult.verified);
      },
    );

    for (var digit = 1; digit <= 4; digit++) {
      await tester.tap(find.byKey(ValueKey('profile-pin-key-$digit')));
    }
    await tester.tap(find.byKey(const ValueKey('profile-pin-submit')));
    await tester.pump();

    expect(submitted, '1234');
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop split layout remains within its viewport', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(1280, 800),
      onSubmit: (_) async =>
          const ProfilePinVerification(ProfilePinResult.verified),
    );

    expect(find.byKey(const Key('profile-pin-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-pin-key-9')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape phone uses a compact split without overflow', (
    tester,
  ) async {
    await pump(
      tester,
      size: const Size(667, 375),
      onSubmit: (_) async =>
          const ProfilePinVerification(ProfilePinResult.verified),
    );

    expect(find.byKey(const Key('profile-pin-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-pin-submit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV DPAD moves across the keypad and activates focused keys', (
    tester,
  ) async {
    String? submitted;
    await pump(
      tester,
      size: const Size(960, 540),
      television: true,
      onSubmit: (pin) async {
        submitted = pin;
        return const ProfilePinVerification(ProfilePinResult.verified);
      },
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit4);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(submitted, '1234');
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('profile-pin-submit'))).dy,
      greaterThan(
        tester
            .getBottomRight(find.byKey(const ValueKey('profile-pin-key-1')))
            .dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV remote back cancels the PIN gate', (tester) async {
    var cancelled = false;
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePinScreen(
          profile: profile,
          onSubmit: (_) async =>
              const ProfilePinVerification(ProfilePinResult.verified),
          onCancel: () => cancelled = true,
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);

    expect(cancelled, isTrue);
  });
}
