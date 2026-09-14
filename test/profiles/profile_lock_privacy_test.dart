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

  testWidgets('native watch suppresses inactivity until its own session ends', (
    tester,
  ) async {
    final controller = ProfileLockController.instance;
    controller.activate(
      _profile(lockOnResume: false, hasPin: false, inactivityTimeoutMinutes: 1),
      unlocked: true,
    );
    final first = controller.beginNativePlayback();
    final second = controller.beginNativePlayback();
    controller.endNativePlayback(first);
    // Disposing a Flutter player must not clear the native watch's lease.
    controller.setPlaybackActive(false);
    await tester.pump(const Duration(minutes: 2));
    expect(controller.isUnlocked, isTrue);
    controller.endNativePlayback(second);
    await tester.pump(const Duration(seconds: 59));
    expect(controller.isUnlocked, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.isUnlocked, isFalse);
  });

  testWidgets('a stale native finish cannot disturb a new profile session', (
    tester,
  ) async {
    final controller = ProfileLockController.instance;
    final profile = _profile(
      lockOnResume: false,
      hasPin: false,
      inactivityTimeoutMinutes: 1,
    );
    controller.activate(profile, unlocked: true);
    final old = controller.beginNativePlayback();
    controller.dispose();
    controller.activate(profile, unlocked: true);
    await tester.pump(const Duration(seconds: 30));
    controller.endNativePlayback(old);
    await tester.pump(const Duration(seconds: 30));
    expect(controller.isUnlocked, isFalse);
  });

  test('native watch does not bypass a PIN lock-on-resume policy', () {
    final controller = ProfileLockController.instance;
    controller.activate(
      _profile(lockOnResume: true, hasPin: true),
      unlocked: true,
    );
    final owner = controller.beginNativePlayback();
    controller.onResume();
    expect(controller.isUnlocked, isFalse);
    controller.endNativePlayback(owner);
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

  test('metadata refresh preserves a lock and rejects another profile', () {
    final original = _profile(lockOnResume: true, hasPin: false);
    ProfileLockController.instance.activate(original, unlocked: true);
    ProfileLockController.instance.lock();

    expect(
      ProfileLockController.instance.refreshProfileIfCurrent(
        _profile(lockOnResume: true, hasPin: true),
      ),
      isTrue,
    );
    expect(ProfileLockController.instance.lockedProfileId.value, original.id);

    expect(
      ProfileLockController.instance.refreshProfileIfCurrent(
        _profileWithId('profile-b'),
      ),
      isFalse,
    );
    expect(ProfileLockController.instance.lockedProfileId.value, original.id);
  });

  test('PIN sync preserves this session and locks exactly once on resume', () {
    final profile = _profile(lockOnResume: false, hasPin: true);
    ProfileLockController.instance.activate(profile, unlocked: true);

    ProfileLockController.instance.armLockOnNextResume(profile.id);
    expect(ProfileLockController.instance.isUnlocked, isTrue);
    expect(
      ProfileLockController.instance.refreshProfileIfCurrent(profile),
      isTrue,
    );
    expect(ProfileLockController.instance.isUnlocked, isTrue);

    ProfileLockController.instance.onResume();
    expect(ProfileLockController.instance.lockedProfileId.value, profile.id);

    ProfileLockController.instance.unlock(profile);
    ProfileLockController.instance.onResume();
    expect(ProfileLockController.instance.isUnlocked, isTrue);
  });

  test('verified PIN before resume satisfies the pending sync lock', () async {
    final controller = ProfileLockController.instance;
    final profile = _profile(lockOnResume: false, hasPin: true);
    controller.activate(profile, unlocked: true);
    controller.armLockOnNextResume(profile.id);
    controller.lock(); // Explicit switch-profile/PIN screen.
    final pending = controller.pendingPinLock(profile.id);

    controller.acknowledgeVerifiedPin(profile.id, pending);
    expect(controller.isUnlocked, isFalse); // Acknowledgment is not an unlock.
    controller.unlock(profile);
    controller.onResume();
    expect(controller.isUnlocked, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect((calls.last.arguments as Map)['protectOnBackground'], isFalse);
  });

  test('generic unlock does not satisfy a pending PIN sync lock', () {
    final controller = ProfileLockController.instance;
    final profile = _profile(lockOnResume: false, hasPin: true);
    controller.activate(profile, unlocked: true);
    controller.armLockOnNextResume(profile.id);
    controller.unlock(profile);
    controller.onResume();
    expect(controller.isUnlocked, isFalse);
  });

  for (final alreadyPending in <bool>[false, true]) {
    test('PIN sync during verification retains its lock ($alreadyPending)', () {
      final controller = ProfileLockController.instance;
      final profile = _profile(lockOnResume: false, hasPin: true);
      controller.activate(profile, unlocked: false);
      if (alreadyPending) controller.armLockOnNextResume(profile.id);
      final pending = controller.pendingPinLock(profile.id);

      // Another sync arrives while the asynchronous PIN verifier is running.
      controller.armLockOnNextResume(profile.id);
      controller.acknowledgeVerifiedPin(profile.id, pending);
      controller.unlock(profile);
      controller.onResume();
      expect(controller.isUnlocked, isFalse);
    });
  }

  test('verification cannot clear another profile or a later session lock', () {
    final controller = ProfileLockController.instance;
    final profile = _profile(lockOnResume: false, hasPin: true);
    controller.activate(profile, unlocked: false);
    controller.armLockOnNextResume(profile.id);
    final pending = controller.pendingPinLock(profile.id);
    controller.acknowledgeVerifiedPin('profile-b', pending);
    expect(controller.pendingPinLock(profile.id), same(pending));

    controller.dispose();
    controller.activate(profile, unlocked: false);
    controller.armLockOnNextResume(profile.id);
    controller.acknowledgeVerifiedPin(profile.id, pending);
    controller.unlock(profile);
    controller.onResume();
    expect(controller.isUnlocked, isFalse);
  });

  test(
    'verified sync PIN preserves the normal lock-on-resume policy',
    () async {
      final controller = ProfileLockController.instance;
      final profile = _profile(lockOnResume: true, hasPin: true);
      controller.activate(profile, unlocked: false);
      controller.armLockOnNextResume(profile.id);
      controller.acknowledgeVerifiedPin(
        profile.id,
        controller.pendingPinLock(profile.id),
      );
      controller.unlock(profile);
      await Future<void>.delayed(Duration.zero);
      expect((calls.last.arguments as Map)['protectOnBackground'], isTrue);
      controller.onResume();
      expect(controller.isUnlocked, isFalse);
    },
  );
}

UserProfile _profile({
  required bool lockOnResume,
  required bool hasPin,
  int? inactivityTimeoutMinutes,
}) {
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
    inactivityTimeoutMinutes: inactivityTimeoutMinutes,
    createdAt: now,
    updatedAt: now,
  );
}

UserProfile _profileWithId(String id) {
  final now = DateTime.utc(2026, 1, 1);
  return UserProfile(
    id: id,
    name: 'Other',
    role: UserProfileRole.member,
    policy: ProfilePolicy.allAllowedFor(UserProfileRole.member),
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
}
