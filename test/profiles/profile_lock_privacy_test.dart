import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.debrify.app/profile_privacy');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'lock-on-resume policy is published before the app backgrounds',
    () async {
      ProfileLockController.instance.activate(
        _profile(lockOnResume: true, hasPin: true),
        unlocked: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, isNotEmpty);
      expect(calls.last.method, 'setSensitive');
      expect(calls.last.arguments, <String, Object?>{
        'sensitive': false,
        'protectOnBackground': true,
      });
    },
  );

  test('locking and teardown publish fail-closed sensitivity', () async {
    final profile = _profile(lockOnResume: false, hasPin: true);
    ProfileLockController.instance.activate(profile, unlocked: true);
    ProfileLockController.instance.lock();
    await Future<void>.delayed(Duration.zero);

    expect((calls.last.arguments as Map)['sensitive'], isTrue);

    ProfileLockController.instance.dispose();
    await Future<void>.delayed(Duration.zero);
    expect((calls.last.arguments as Map)['sensitive'], isTrue);
  });
}

UserProfile _profile({required bool lockOnResume, required bool hasPin}) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    id: 'profile-a',
    name: 'Profile A',
    role: UserProfileRole.admin,
    policy: ProfilePolicy.allAllowedFor(UserProfileRole.admin),
    authorizationRevision: 1,
    lifecycle: UserProfileLifecycle.active,
    visibleDataGeneration: 1,
    setupComplete: true,
    pinResetRequired: false,
    hasPin: hasPin,
    lockOnResume: lockOnResume,
    createdAt: now,
    updatedAt: now,
  );
}
