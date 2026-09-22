import 'dart:convert';

import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceSecretChannel = MethodChannel('debrify/device_secret');
  void restart() {
    DeviceKeyProvider.debugReset();
    DeviceKeyProvider.debugLinuxOverride = true;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    restart();
  });
  tearDown(() {
    DeviceKeyProvider.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, null);
  });

  test(
    'native sealing verifies the complete payload with the same AAD',
    () async {
      final plaintext = List<int>.generate(96 * 1024, (i) => i % 256);
      final aad = utf8.encode('resource metadata');
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceSecretChannel, (call) async {
            methods.add(call.method);
            final args = call.arguments as Map;
            expect(base64Decode(args['associatedData'] as String), aad);
            if (call.method == 'seal') {
              expect(base64Decode(args['plaintext'] as String), plaintext);
              return 'candidate';
            }
            expect(args['envelope'], 'candidate');
            return base64Encode(plaintext);
          });
      expect(
        await PlatformDeviceSecretCipher().seal(plaintext, associatedData: aad),
        'native1:candidate',
      );
      expect(methods, ['seal', 'open']);
    },
  );

  test(
    'native sealing rejects successful decryption of different bytes',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            deviceSecretChannel,
            (call) async =>
                call.method == 'seal' ? 'candidate' : base64Encode([1, 2]),
          );
      await expectLater(
        PlatformDeviceSecretCipher().seal([1, 3], associatedData: []),
        throwsA(
          isA<DeviceVaultException>().having(
            (e) => e.operation,
            'operation',
            'seal',
          ),
        ),
      );
    },
  );

  test(
    'record authentication failure never authorizes a vault reset',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(deviceSecretChannel, (_) async {
            throw PlatformException(code: 'device_secret_record_unreadable');
          });
      await expectLater(
        PlatformDeviceSecretCipher().open('native1:record', associatedData: []),
        throwsA(
          isA<DeviceVaultException>()
              .having(
                (e) => e.failure,
                'failure',
                DeviceVaultFailure.recordUnreadable,
              )
              .having((e) => e.requiresReset, 'requiresReset', isFalse),
        ),
      );
    },
  );

  test('existing native vault initialization forbids key creation', () async {
    DeviceKeyProvider.debugLinuxOverride = false;
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          received = call;
          return true;
        });

    await DeviceKeyProvider.initialize(allowCreate: false);

    expect(received?.method, 'initialize');
    expect(received?.arguments, <String, Object>{'allowCreate': false});
    expect(DeviceKeyProvider.isInitialized, isTrue);
  });

  test('missing native key is classified without replacing it', () async {
    DeviceKeyProvider.debugLinuxOverride = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          throw PlatformException(
            code: 'device_secret_missing',
            message:
                'initialize:DeviceSecretMissingException:DeviceSecretMissingException',
          );
        });

    await expectLater(
      DeviceKeyProvider.initialize(allowCreate: false),
      throwsA(
        isA<DeviceVaultException>()
            .having(
              (error) => error.failure,
              'failure',
              DeviceVaultFailure.missing,
            )
            .having((error) => error.requiresReset, 'requiresReset', isTrue),
      ),
    );
    expect(DeviceKeyProvider.isInitialized, isFalse);
    expect(DeviceKeyProvider.isUnlocked, isFalse);
  });

  test('pre-canary native vault waits for the resource audit', () async {
    DeviceKeyProvider.debugLinuxOverride = false;
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceSecretChannel, (call) async {
          methods.add(call.method);
          if (call.method == 'initialize') return 'migration_audit_required';
          if (call.method == 'commitMigrationAudit') return true;
          return null;
        });

    await DeviceKeyProvider.initialize(allowCreate: false);
    expect(DeviceKeyProvider.requiresMigrationAudit, isTrue);

    await DeviceKeyProvider.commitMigrationAudit();

    expect(DeviceKeyProvider.requiresMigrationAudit, isFalse);
    expect(methods, <String>['initialize', 'commitMigrationAudit']);
  });

  test('fresh Linux vault opens automatically across launches', () async {
    await Future.wait([
      DeviceKeyProvider.initialize(),
      DeviceKeyProvider.initialize(),
    ]);
    expect(DeviceKeyProvider.linuxAutoUnlockEnabled, isTrue);
    final sealed = await DeviceKeyProvider.cipher.seal(
      [1, 2, 3],
      associatedData: [4],
    );
    restart();
    await DeviceKeyProvider.initialize();
    expect(await DeviceKeyProvider.cipher.open(sealed, associatedData: [4]), [
      1,
      2,
      3,
    ]);
  });

  test(
    'legacy vault requires one valid unlock and preserves ciphertext after conversion',
    () async {
      await DeviceKeyProvider.createLinuxVault('old passphrase');
      final sealed = await DeviceKeyProvider.cipher.seal(
        [5, 6],
        associatedData: [7],
      );
      restart();
      await DeviceKeyProvider.initialize();
      expect(DeviceKeyProvider.isUnlocked, isFalse);
      await expectLater(
        DeviceKeyProvider.unlockLinuxVault('wrong password'),
        throwsA(anything),
      );
      expect(DeviceKeyProvider.isUnlocked, isFalse);
      await DeviceKeyProvider.unlockLinuxVault('old passphrase');
      await DeviceKeyProvider.enableLinuxAutoUnlock();
      restart();
      await DeviceKeyProvider.initialize();
      expect(await DeviceKeyProvider.cipher.open(sealed, associatedData: [7]), [
        5,
        6,
      ]);
    },
  );

  test(
    'restoring passphrase protection preserves secrets and removes local access',
    () async {
      await DeviceKeyProvider.initialize();
      final sealed = await DeviceKeyProvider.cipher.seal([
        8,
      ], associatedData: []);
      await DeviceKeyProvider.changeLinuxPassphrase('new passphrase');
      expect(DeviceKeyProvider.linuxAutoUnlockEnabled, isFalse);
      restart();
      await DeviceKeyProvider.initialize();
      expect(DeviceKeyProvider.isUnlocked, isFalse);
      await DeviceKeyProvider.unlockLinuxVault('new passphrase');
      expect(await DeviceKeyProvider.cipher.open(sealed, associatedData: []), [
        8,
      ]);
    },
  );

  test('malformed persisted key is preserved and never replaced', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DeviceKeyProvider.linuxStateKey, 'broken');
    await expectLater(DeviceKeyProvider.initialize(), throwsA(anything));
    expect(DeviceKeyProvider.isUnlocked, isFalse);
    expect(DeviceKeyProvider.isInitialized, isFalse);
    expect(prefs.getString(DeviceKeyProvider.linuxStateKey), 'broken');
  });

  test(
    'startup and restoring protection remove scoped copies across generations',
    () async {
      await DeviceKeyProvider.initialize();
      final prefs = await SharedPreferences.getInstance();
      const key = DeviceKeyProvider.linuxStateKey;
      final deviceState = prefs.getString(key)!;
      final sealed = await DeviceKeyProvider.cipher.seal([
        9,
      ], associatedData: []);
      await prefs.setString('p.admin.g.1.$key', deviceState);
      await prefs.setString('p.member.g.3.$key', deviceState);
      await prefs.setString('p.admin.g.1.${key}_unrelated', 'keep');
      await prefs.setString('p.admin.g.1.theme', 'dark');
      restart();
      await DeviceKeyProvider.initialize();
      expect(prefs.containsKey('p.admin.g.1.$key'), isFalse);
      expect(prefs.containsKey('p.member.g.3.$key'), isFalse);
      expect(prefs.getString(key), deviceState);
      // Also remove copies introduced during this session before protecting it.
      await prefs.setString('p.admin.g.2.$key', deviceState);
      await DeviceKeyProvider.changeLinuxPassphrase('protected again');
      expect(prefs.containsKey('p.admin.g.2.$key'), isFalse);
      expect(prefs.getString('p.admin.g.1.${key}_unrelated'), 'keep');
      expect(prefs.getString('p.admin.g.1.theme'), 'dark');
      restart();
      await DeviceKeyProvider.initialize();
      expect(DeviceKeyProvider.isUnlocked, isFalse);
      await DeviceKeyProvider.unlockLinuxVault('protected again');
      expect(await DeviceKeyProvider.cipher.open(sealed, associatedData: []), [
        9,
      ]);
    },
  );

  test('destroy removes automatic unlock state', () async {
    await DeviceKeyProvider.initialize();
    await DeviceKeyProvider.destroy();
    expect(await DeviceKeyProvider.linuxHasWrappedKey(), isFalse);
    expect(DeviceKeyProvider.isUnlocked, isFalse);
  });
}
