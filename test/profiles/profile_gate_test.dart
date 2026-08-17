import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sole unpinned profile auto-enters only during startup', () {
    final admin = _profile();

    expect(
      shouldAutoEnterSoleProfile(<UserProfile>[
        admin,
      ], allowSingleProfileAutoEnter: true),
      isTrue,
    );
    expect(
      shouldAutoEnterSoleProfile(<UserProfile>[
        admin,
      ], allowSingleProfileAutoEnter: false),
      isFalse,
    );
  });

  test('startup never auto-enters a protected profile', () {
    expect(
      shouldAutoEnterSoleProfile(<UserProfile>[
        _profile(hasPin: true),
      ], allowSingleProfileAutoEnter: true),
      isFalse,
    );
    expect(
      shouldAutoEnterSoleProfile(<UserProfile>[
        _profile(pinResetRequired: true),
      ], allowSingleProfileAutoEnter: true),
      isFalse,
    );
  });

  // The gate composes the two: startup passes `allowSingleProfileAutoEnter:
  // true` but ANDs it with `!ProfileGateAlwaysAsk.cached`, so the fresh-
  // install default (ask) wins until the hub's startup toggle opts out.
  test('always-ask defaults on and the opt-out persists', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ProfileGateAlwaysAsk.warm();
    expect(ProfileGateAlwaysAsk.cached, isTrue);

    await ProfileGateAlwaysAsk.set(false);
    ProfileGateAlwaysAsk.cached = true; // prove warm() reads storage
    await ProfileGateAlwaysAsk.warm();
    expect(ProfileGateAlwaysAsk.cached, isFalse);
  });
}

UserProfile _profile({bool hasPin = false, bool pinResetRequired = false}) {
  final now = DateTime.utc(2026, 8, 13);
  return UserProfile(
    id: 'admin',
    name: 'Admin',
    role: UserProfileRole.admin,
    policy: ProfilePolicy.defaultsFor(UserProfileRole.admin),
    authorizationRevision: 1,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: pinResetRequired,
    hasPin: hasPin,
    lockOnResume: false,
    createdAt: now,
    updatedAt: now,
  );
}
