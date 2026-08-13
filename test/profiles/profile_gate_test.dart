import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:flutter_test/flutter_test.dart';

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
