import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/screens/profiles/profile_picker_screen.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 14);
  late UserProfile profile;

  setUp(() {
    profile = UserProfile(
      id: 'admin-v1',
      name: 'Meera',
      avatarKey: 'art:aurora',
      role: UserProfileRole.admin,
      policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
      authorizationRevision: 1,
      lifecycle: UserProfileLifecycle.active,
      visibleDataGeneration: 1,
      setupComplete: true,
      pinResetRequired: false,
      hasPin: false,
      lockOnResume: false,
      createdAt: now,
      updatedAt: now,
    );
  });

  bool artIsAnimating(WidgetTester tester) => tester
      .widget<CustomPaint>(find.byKey(ProfileAvatarView.artPaintKey))
      .willChange;

  testWidgets('Manage focus clears the last profile focus and animation', (
    tester,
  ) async {
    // The focus-only animation contract is TV's — on touch the tile keeps
    // living regardless of focus (the next test). Pin the platform so this
    // keeps guarding the TV behavior it was written for.
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileWallScreen(
          profiles: <UserProfile>[profile],
          onSelected: (_) {},
          onManage: () {},
        ),
      ),
    );
    expect(artIsAnimating(tester), isTrue);

    Focus.of(tester.element(find.text('Manage profiles'))).requestFocus();
    await tester.pump();

    expect(artIsAnimating(tester), isFalse);
  });

  testWidgets('touch keeps the avatar living when focus leaves the tile', (
    tester,
  ) async {
    // No cursor on touch, so focus-gated animation would mean a chosen GIF
    // or living art never moves at all — the wall opts in to idle animation
    // off TV (2026-08-16 report: "I thought GIFs would act as GIFs").
    PlatformUtil.debugSetAndroidTvCached(false);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileWallScreen(
          profiles: <UserProfile>[profile],
          onSelected: (_) {},
          onManage: () {},
        ),
      ),
    );
    expect(artIsAnimating(tester), isTrue);

    Focus.of(tester.element(find.text('Manage profiles'))).requestFocus();
    await tester.pump();

    expect(artIsAnimating(tester), isTrue);
  });

  testWidgets('the classic picker renders the selected avatar kind', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfilePickerScreen(
          profiles: <UserProfile>[profile],
          onSelected: (_) {},
        ),
      ),
    );

    expect(find.byKey(ProfileAvatarView.artPaintKey), findsOneWidget);
    expect(find.byIcon(Icons.person_rounded), findsNothing);
  });
}
