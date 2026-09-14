import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void restart() {
    DeviceKeyProvider.debugReset();
    DeviceKeyProvider.debugLinuxOverride = true;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    restart();
  });
  tearDown(DeviceKeyProvider.debugReset);

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
