import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/screens/settings/self_profile_settings_page.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory root;
  late ProfileRegistry registry;
  late String memberId;
  late UserProfile member;
  late ProfileAuthorizationContext authorization;
  late ProfilePinService pins;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('self-profile-page-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    ProfileAvatarPolicy.debugSetUserImagesSupported(false);
    registry = await ProfileRegistry.open(
      path: p.join(root.path, 'profiles.db'),
    );
    final admin = await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    );
    member = await registry.createProfile(
      name: 'Maya',
      role: UserProfileRole.member,
      policy: const ProfilePolicy(
        enabled: <ProfileFeature>{ProfileFeature.cloud},
      ),
    );
    memberId = member.id;
    await registry.commitBootstrap(
      activeProfileId: admin.id,
      migratedLegacyInstall: false,
    );
    await registry.setActiveProfile(memberId);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 2),
    );
    ProfileLockController.instance.unlock(member);
    authorization = await ProfileAuthorizationContext.capture(registry);
    pins = ProfilePinService(
      registry: registry,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    ProfileAvatarPolicy.debugSetUserImagesSupported(null);
    AppStorage.debugReset();
    await registry.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> waitFor(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(condition(), isTrue, reason: 'Async checkpoint did not complete');
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: SelfProfileSettingsPage(
          registry: registry,
          pins: pins,
          authorization: authorization,
          profile: member,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('self editor renders only identity and PIN controls', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byKey(const ValueKey('self-profile-name')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('self-profile-save-identity')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('self-profile-new-pin')), findsOneWidget);
    expect(find.text('ROLE'), findsNothing);
    expect(find.text('Permissions'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('identity save persists without changing access', (tester) async {
    final before = member;
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('self-profile-name')),
      'Maya Two',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('self-avatar-child')));
    await tester.tap(find.byKey(const ValueKey('self-avatar-child')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-save-identity')),
    );
    await tester.tap(find.byKey(const ValueKey('self-profile-save-identity')));
    await settle(tester, rounds: 16);

    UserProfile? after;
    await tester.runAsync(() async {
      after = await registry.getProfile(memberId);
    });
    expect(after?.name, 'Maya Two');
    expect(after?.avatarKey, 'child');
    expect(after?.role, before.role);
    expect(after?.policy.encode(), before.policy.encode());
    expect(after?.authorizationRevision, before.authorizationRevision);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name-only save preserves a role-default avatar', (tester) async {
    expect(member.avatarKey, isNull);
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const ValueKey('self-profile-name')),
      'Maya Renamed',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-save-identity')),
    );
    await tester.tap(find.byKey(const ValueKey('self-profile-save-identity')));
    await settle(tester, rounds: 16);

    UserProfile? after;
    await tester.runAsync(() async {
      after = await registry.getProfile(memberId);
    });
    expect(after?.name, 'Maya Renamed');
    expect(after?.avatarKey, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Member can set a PIN and receives its one-time recovery code', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-new-pin')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('self-profile-new-pin')),
      '4826',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self-profile-confirm-pin')),
      '4826',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-change-pin')),
    );
    await tester.tap(find.byKey(const ValueKey('self-profile-change-pin')));
    await settle(tester);

    expect(find.text('Save this recovery code'), findsOneWidget);
    ProfilePinRecord? record;
    await tester.runAsync(() async {
      record = await registry.getPinRecord(memberId);
    });
    expect(record?.hasPin, isTrue);
    expect(record?.hasRecoveryCode, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an intervening lock is preserved when PIN save completes', (
    tester,
  ) async {
    await pumpPage(tester);
    var lockOnCheckpoint = true;
    var checkpointLocked = false;
    registry.authorityChangedCallback = () async {
      if (!lockOnCheckpoint) return;
      lockOnCheckpoint = false;
      ProfileLockController.instance.lock();
      checkpointLocked = true;
    };

    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-new-pin')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('self-profile-new-pin')),
      '4826',
    );
    await tester.enterText(
      find.byKey(const ValueKey('self-profile-confirm-pin')),
      '4826',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('self-profile-change-pin')),
    );
    await tester.tap(find.byKey(const ValueKey('self-profile-change-pin')));
    await waitFor(tester, () => checkpointLocked);
    await settle(tester, rounds: 16);

    expect(ProfileLockController.instance.lockedProfileId.value, memberId);
    expect(find.text('Save this recovery code'), findsNothing);
    ProfilePinRecord? record;
    await tester.runAsync(() async {
      record = await registry.getPinRecord(memberId);
    });
    expect(record?.hasPin, isTrue);
    expect(tester.takeException(), isNull);
  });
}
