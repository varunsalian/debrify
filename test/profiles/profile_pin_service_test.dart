import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late ProfilePinService pins;
  late String adminId;
  late String profileId;
  final now = DateTime(2026, 8, 13, 12);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('pin-test-');
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    profileId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    pins = ProfilePinService(
      registry: registry,
      clock: () => now,
      params: const PinKdfParams(memory: 64, iterations: 1),
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileLockController.instance.dispose();
    ProfileRuntime.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> setMemberPin(String pin) async {
    await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: pin,
    );
  }

  Future<ProfileAuthorizationContext> activateMember() async {
    await registry.setActiveProfile(profileId);
    ProfileRuntime.publish(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 2),
    );
    ProfileLockController.instance.unlock(
      (await registry.getProfile(profileId))!,
    );
    return ProfileAuthorizationContext.capture(registry);
  }

  test('Member can set, replace and remove only their own PIN', () async {
    final actor = await activateMember();
    final firstRecovery = await pins.setOwnPin(actor: actor, newPin: '4826');
    expect(firstRecovery, isNotEmpty);
    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.verified,
    );

    final secondRecovery = await pins.setOwnPin(
      actor: actor,
      currentPin: '4826',
      newPin: '9151',
    );
    expect(secondRecovery, isNot(firstRecovery));
    expect(
      (await pins.verify(profileId, '9151')).result,
      ProfilePinResult.verified,
    );

    await pins.removeOwnPin(actor: actor, currentPin: '9151');
    expect((await registry.getPinRecord(profileId))?.hasPin, isFalse);
  });

  test('self-service PIN replacement requires the current PIN', () async {
    await setMemberPin('4826');
    final actor = await activateMember();

    await expectLater(
      pins.setOwnPin(actor: actor, currentPin: '0000', newPin: '9151'),
      throwsA(isA<ProfileCurrentPinException>()),
    );
    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.verified,
    );
    expect(
      (await pins.verify(profileId, '9151')).result,
      ProfilePinResult.invalid,
    );
  });

  test(
    'self-service cannot overwrite a credential changed after verification',
    () async {
      await setMemberPin('4826');
      final actor = await activateMember();
      var injectReset = true;
      registry.authorityChangedCallback = () async {
        if (!injectReset) return;
        injectReset = false;
        final current = await registry.getPinRecord(profileId);
        if (current == null) return;
        await registry.markPinResetRequiredIfUnchanged(
          profileId: profileId,
          expected: current,
        );
      };

      await expectLater(
        pins.setOwnPin(actor: actor, currentPin: '4826', newPin: '9151'),
        throwsStateError,
      );

      final record = await registry.getPinRecord(profileId);
      expect(record?.resetRequired, isTrue);
      expect(
        (await pins.verify(profileId, '9151')).result,
        ProfilePinResult.resetRequired,
      );
    },
  );

  test(
    'self-service conditional writes include recovery credentials',
    () async {
      await setMemberPin('4826');
      final actor = await activateMember();
      final actual = (await registry.getPinRecord(profileId))!;
      final unverified = ProfilePinRecord(
        hash: actual.hash,
        salt: actual.salt,
        paramsJson: actual.paramsJson,
        resetRequired: actual.resetRequired,
        recoveryHash: Uint8List.fromList(List<int>.filled(32, 7)),
        recoverySalt: actual.recoverySalt,
        recoveryParamsJson: actual.recoveryParamsJson,
      );

      await expectLater(
        registry.setActiveProfilePinRecordIfUnchanged(
          profileId: profileId,
          expected: unverified,
          hash: null,
          salt: null,
          paramsJson: null,
          recoveryHash: null,
          recoverySalt: null,
          recoveryParamsJson: null,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        ),
        throwsStateError,
      );
      expect((await registry.getPinRecord(profileId))?.hasPin, isTrue);
      expect((await registry.getPinRecord(profileId))?.hasRecoveryCode, isTrue);
    },
  );

  test(
    'a switched self-service session cannot change the old profile PIN',
    () async {
      final actor = await activateMember();
      await registry.setActiveProfile(adminId);
      ProfileRuntime.publish(
        ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 3),
      );
      var invalidations = 0;
      var republications = 0;
      registry.authorityWillChangeCallback = () async {
        invalidations++;
      };
      registry.authorityChangedCallback = () async {
        republications++;
      };

      await expectLater(
        pins.setOwnPin(actor: actor, newPin: '4826'),
        throwsStateError,
      );
      expect((await registry.getPinRecord(profileId))?.hasPin, isFalse);
      expect(invalidations, 0);
      expect(republications, 0);

      final expected = (await registry.getPinRecord(profileId))!;
      await expectLater(
        registry.setActiveProfilePinRecordIfUnchanged(
          profileId: profileId,
          expected: expected,
          hash: null,
          salt: null,
          paramsJson: null,
          recoveryHash: null,
          recoverySalt: null,
          recoveryParamsJson: null,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        ),
        throwsStateError,
      );
      expect(invalidations, 1);
      expect(republications, 1);
    },
  );

  test(
    'a committed self PIN retries publication before returning success',
    () async {
      final actor = await activateMember();
      var publicationAttempts = 0;
      registry.authorityChangedCallback = () async {
        publicationAttempts++;
        if (publicationAttempts <= 2) {
          throw StateError('native publication temporarily unavailable');
        }
      };

      final recoveryCode = await pins.setOwnPin(actor: actor, newPin: '4826');

      expect(recoveryCode, isNotEmpty);
      expect(publicationAttempts, 3);
      final committed = await registry.getPinRecord(profileId);
      expect(committed?.hasPin, isTrue);
      expect(committed?.hasRecoveryCode, isTrue);

      registry.authorityChangedCallback = null;
      expect(
        await pins.verifyRecoveryCode(profileId, recoveryCode),
        ProfileRecoveryResult.cleared,
      );
    },
  );

  test('a persistently unpublishable PIN is not reported as success and keeps '
      'its recovery code', () async {
    final actor = await activateMember();
    registry.authorityChangedCallback = () async {
      throw StateError('native publication unavailable');
    };

    ProfilePinDurabilityException? failure;
    try {
      await pins.setOwnPin(actor: actor, newPin: '4826');
    } on ProfilePinDurabilityException catch (error) {
      failure = error;
    }

    expect(failure, isNotNull);
    expect(failure?.recoveryCode, isNotEmpty);
    expect((await registry.getPinRecord(profileId))?.hasPin, isTrue);
    registry.authorityChangedCallback = null;
    expect(
      await pins.verifyRecoveryCode(profileId, failure!.recoveryCode!),
      ProfileRecoveryResult.cleared,
    );
  });

  test('a committed PIN removal retries publication before success', () async {
    await setMemberPin('4826');
    final actor = await activateMember();
    var publicationAttempts = 0;
    registry.authorityWillChangeCallback = () async {
      registry.authorityChangedCallback = () async {
        publicationAttempts++;
        if (publicationAttempts <= 2) {
          throw StateError('native publication temporarily unavailable');
        }
      };
    };

    await pins.removeOwnPin(actor: actor, currentPin: '4826');

    expect(publicationAttempts, 3);
    expect((await registry.getPinRecord(profileId))?.hasPin, isFalse);
  });

  test(
    'a persistently unpublishable PIN removal reports a durability error',
    () async {
      await setMemberPin('4826');
      final actor = await activateMember();
      registry.authorityWillChangeCallback = () async {
        registry.authorityChangedCallback = () async {
          throw StateError('native publication unavailable');
        };
      };

      await expectLater(
        pins.removeOwnPin(actor: actor, currentPin: '4826'),
        throwsA(isA<ProfilePinDurabilityException>()),
      );
      expect((await registry.getPinRecord(profileId))?.hasPin, isFalse);
    },
  );

  test(
    'a concurrent reset is not mistaken for a committed PIN removal',
    () async {
      await setMemberPin('4826');
      final actor = await activateMember();
      var injectReset = true;
      registry.authorityChangedCallback = () async {
        if (!injectReset) return;
        injectReset = false;
        final current = await registry.getPinRecord(profileId);
        if (current == null) return;
        await registry.markPinResetRequiredIfUnchanged(
          profileId: profileId,
          expected: current,
        );
      };

      await expectLater(
        pins.removeOwnPin(actor: actor, currentPin: '4826'),
        throwsStateError,
      );

      final record = await registry.getPinRecord(profileId);
      expect(record?.resetRequired, isTrue);
      expect(record?.hasPin, isFalse);
      expect(record?.hasRecoveryCode, isFalse);
    },
  );

  test('sets and verifies a numeric PIN without storing it', () async {
    await setMemberPin('4826');
    final record = await registry.getPinRecord(profileId);

    expect(record?.hasPin, isTrue);
    expect(record?.hash, isNot(containsAll(<int>[52, 56, 50, 54])));
    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.verified,
    );
    expect((await registry.getPinRecord(profileId))?.failedAttempts, 0);
  });

  test('locks only after the 100-attempt household allowance', () async {
    // Product call 2026-08: a family fumbling a shared remote never sees a
    // lock; only sustained (scripted-scale) guessing does.
    await setMemberPin('4826');
    for (var attempt = 0; attempt < 99; attempt++) {
      final failed = await pins.verify(profileId, '0000');
      expect(failed.result, ProfilePinResult.invalid);
      expect(failed.lockedUntil, isNull);
    }

    final hundredth = await pins.verify(profileId, '0000');
    expect(hundredth.result, ProfilePinResult.invalid);
    expect(hundredth.lockedUntil, now.add(const Duration(seconds: 30)));

    final locked = await pins.verify(profileId, '4826');
    expect(locked.result, ProfilePinResult.locked);
    expect(locked.lockedUntil, now.add(const Duration(seconds: 30)));
  });

  test('recovery code removes the PIN once, forgivingly typed', () async {
    final code = await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );
    expect(
      code,
      matches(RegExp(r'^[A-HJ-KM-NP-Z2-9]{5}-[A-HJ-KM-NP-Z2-9]{5}$')),
    );

    expect(
      await pins.verifyRecoveryCode(profileId, 'AAAAA-AAAAA'),
      ProfileRecoveryResult.invalid,
    );
    expect((await registry.getPinRecord(profileId))?.hasPin, isTrue);

    // Case, spacing, and dashes must never matter.
    final sloppy = code.toLowerCase().replaceAll('-', ' ');
    expect(
      await pins.verifyRecoveryCode(profileId, sloppy),
      ProfileRecoveryResult.cleared,
    );
    final record = await registry.getPinRecord(profileId);
    expect(record?.hasPin, isFalse);
    expect(record?.hasRecoveryCode, isFalse);
    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.notConfigured,
    );

    // Spent: the same code can never open anything again.
    expect(
      await pins.verifyRecoveryCode(profileId, code),
      ProfileRecoveryResult.notConfigured,
    );
  });

  test('recovery code rotates with the PIN and dies with it', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    final first = await pins.setPinAsAdmin(
      actor: actor,
      targetProfileId: profileId,
      pin: '4826',
    );
    final second = await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '9151',
    );
    expect(first, isNot(second));
    expect(
      await pins.verifyRecoveryCode(profileId, first),
      ProfileRecoveryResult.invalid,
    );

    await pins.removePinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
    );
    expect((await registry.getPinRecord(profileId))?.hasRecoveryCode, isFalse);
    expect(
      await pins.verifyRecoveryCode(profileId, second),
      ProfileRecoveryResult.notConfigured,
    );
  });

  test('recovery cannot undo an Admin-required reset', () async {
    // Admin-reset is a deliberate lockdown (possibly a compromised PIN);
    // the pre-reset recovery code must not convert it into an unpinned
    // profile.
    final code = await pins.setPinAsAdmin(
      actor: await ProfileAuthorizationContext.capture(registry),
      targetProfileId: profileId,
      pin: '4826',
    );
    await pins.requireAdminReset(profileId);

    expect(
      await pins.verifyRecoveryCode(profileId, code),
      ProfileRecoveryResult.notConfigured,
    );
    // The lockdown holds: still reset-required (never "unpinned"), and the
    // pre-reset code is gone rather than lingering.
    final record = await registry.getPinRecord(profileId);
    expect(record?.resetRequired, isTrue);
    expect(record?.hasRecoveryCode, isFalse);
    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.resetRequired,
    );
  });

  test('a v3 registry gains recovery columns on upgrade', () async {
    // Build the pre-recovery schema by stripping the v4 columns, stamp it
    // version 3, and prove ProfileRegistry.open migrates it in place.
    final path = p.join(temporaryDirectory.path, 'upgrade.db');
    final legacy = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          for (final statement in ProfileRegistry.debugSchemaStatements) {
            await db.execute(
              statement
                  .replaceAll('recovery_hash BLOB,', '')
                  .replaceAll('recovery_salt BLOB,', '')
                  .replaceAll('recovery_params_json TEXT,', '')
                  .replaceAll(
                    '      secret_pending INTEGER NOT NULL DEFAULT 0,\n',
                    '',
                  )
                  .replaceAll(
                    '      updated_at_ms INTEGER NOT NULL DEFAULT 0,\n',
                    '',
                  ),
            );
          }
        },
      ),
    );
    await legacy.close();

    final upgraded = await ProfileRegistry.open(path: path);
    try {
      final memberId = (await upgraded.createProfile(
        name: 'Upgraded',
        role: UserProfileRole.member,
      )).id;
      final upgradedAdminId = (await upgraded.createProfile(
        name: 'UpgradedAdmin',
        role: UserProfileRole.admin,
      )).id;
      await upgraded.commitBootstrap(
        activeProfileId: upgradedAdminId,
        migratedLegacyInstall: false,
      );
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(
        ProfileScope(
          profileId: upgradedAdminId,
          dataGeneration: 1,
          sessionEpoch: 1,
        ),
      );
      final upgradedPins = ProfilePinService(
        registry: upgraded,
        clock: () => now,
        params: const PinKdfParams(memory: 64, iterations: 1),
      );
      final code = await upgradedPins.setPinAsAdmin(
        actor: await ProfileAuthorizationContext.capture(upgraded),
        targetProfileId: memberId,
        pin: '4826',
      );
      expect(
        await upgradedPins.verifyRecoveryCode(memberId, code),
        ProfileRecoveryResult.cleared,
      );
    } finally {
      await upgraded.close();
    }
  });

  test('Admin reset state never behaves like an unpinned profile', () async {
    await setMemberPin('4826');
    await pins.requireAdminReset(profileId);

    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.resetRequired,
    );
  });

  test('rejects non-numeric and out-of-range PINs', () async {
    expect(() => pins.setPin(profileId, '123'), throwsArgumentError);
    expect(() => pins.setPin(profileId, 'abcd'), throwsArgumentError);
    expect(() => pins.setPin(profileId, '123456789'), throwsArgumentError);
  });

  test('malformed stored KDF parameters require Admin reset', () async {
    final actor = await ProfileAuthorizationContext.capture(registry);
    await registry.setPinRecord(
      profileId: profileId,
      hash: List<int>.filled(32, 1),
      salt: List<int>.filled(16, 2),
      paramsJson:
          '{"version":1,"memory":999999999,"iterations":1,"parallelism":1}',
      actingProfileId: actor.profileId,
      actingAuthorizationRevision: actor.authorizationRevision,
      actingSessionEpoch: actor.sessionEpoch,
    );

    expect(
      (await pins.verify(profileId, '4826')).result,
      ProfilePinResult.resetRequired,
    );
    expect((await registry.getPinRecord(profileId))?.resetRequired, isTrue);
  });

  test('registry rejects partially present PIN records', () async {
    expect(
      () => registry.setPinRecord(
        profileId: profileId,
        hash: List<int>.filled(32, 1),
        salt: null,
        paramsJson: null,
      ),
      throwsArgumentError,
    );
  });

  test('committed PIN writes require a live Admin capability', () async {
    await expectLater(pins.setPin(profileId, '4826'), throwsStateError);
    expect((await registry.getPinRecord(profileId))?.hasPin, isFalse);
  });

  test(
    'stale PIN verification cannot authenticate after Admin reset',
    () async {
      await setMemberPin('4826');
      final stale = (await registry.getPinRecord(profileId))!;
      await setMemberPin('9371');

      expect(
        await registry.completePinVerificationIfUnchanged(
          profileId: profileId,
          expected: stale,
        ),
        isFalse,
      );
      expect(
        (await pins.verify(profileId, '9371')).result,
        ProfilePinResult.verified,
      );
      expect(
        (await pins.verify(profileId, '4826')).result,
        ProfilePinResult.invalid,
      );
    },
  );

  test('Admin PIN reset revalidates the active authorization', () async {
    final admin = await ProfileAuthorizationContext.capture(registry);
    await pins.setPinAsAdmin(
      actor: admin,
      targetProfileId: profileId,
      pin: '4826',
    );
    expect((await registry.getPinRecord(profileId))?.hasPin, isTrue);

    ProfileRuntime.publish(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 2),
    );
    final member = await ProfileAuthorizationContext.capture(registry);
    expect(
      () => pins.removePinAsAdmin(actor: member, targetProfileId: profileId),
      throwsStateError,
    );
  });
}
