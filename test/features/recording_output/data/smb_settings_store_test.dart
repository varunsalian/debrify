import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/data/smb_settings_store.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

SmbSettingsStore _plainStore() => SmbSettingsStore(
  seal: (plain) async => 'sealed:$plain',
  open: (stored) async => stored != null && stored.startsWith('sealed:')
      ? stored.substring(7)
      : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'smb-store-test-device');
  });

  test('is the coordinator settings boundary', () {
    expect(_plainStore(), isA<SmbUploadSettings>());
  });

  test('keys are the registered device keys', () {
    expect(SmbSettingsStore.targetKey, 'recording_smb_target_v1');
    expect(SmbSettingsStore.passwordKey, 'recording_smb_password_v1');
    expect(SmbSettingsStore.ledgerKey, 'recording_smb_uploads_v1');
    for (final key in [
      SmbSettingsStore.targetKey,
      SmbSettingsStore.passwordKey,
      SmbSettingsStore.ledgerKey,
    ]) {
      expect(DevicePreferences.allowedKeys, contains(key));
    }
  });

  test('target defaults, then round trips through device storage', () async {
    final store = _plainStore();
    expect(await store.readTarget(), const SmbTarget());
    const t = SmbTarget(enabled: true, host: 'nas', share: 'rec', folder: 'TV');
    await store.writeTarget(t);
    expect(await _plainStore().readTarget(), t);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('recording_smb_target_v1'), t.encode());
  });

  test('password is sealed at rest and removable', () async {
    final store = _plainStore();
    expect(await store.readPassword(), isNull);
    await store.writePassword('hunter2');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('recording_smb_password_v1'), 'sealed:hunter2');
    expect(await store.readPassword(), 'hunter2');

    await store.writePassword('');
    expect(prefs.containsKey('recording_smb_password_v1'), isFalse);
    await store.writePassword('again');
    await store.writePassword(null);
    expect(prefs.containsKey('recording_smb_password_v1'), isFalse);
    expect(await store.readPassword(), isNull);
  });

  test('default cipher is SecretVault', () async {
    final store = SmbSettingsStore();
    await store.writePassword('pa55');
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('recording_smb_password_v1')!;
    expect(stored, isNot(contains('pa55')));
    expect(stored, startsWith(SecretVault.prefix));
    expect(await SmbSettingsStore().readPassword(), 'pa55');
  });

  test('ledger round trips', () async {
    final store = _plainStore();
    expect((await store.readLedger()).records, isEmpty);
    final ledger = const SmbUploadLedger().withRecord(
      const SmbUploadRecord(
        uri: 'content://x',
        bytes: 5,
        state: SmbUploadState.uploaded,
        remotePath: 'TV/x.ts',
        updatedAtMs: 3,
      ),
    );
    await store.writeLedger(ledger);
    final back = await _plainStore().readLedger();
    expect(back['content://x'], ledger['content://x']);
  });

  test('corrupt stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      'recording_smb_target_v1': '{broken',
      'recording_smb_uploads_v1': 'nope',
      'recording_smb_password_v1': 'not-sealed',
    });
    final store = _plainStore();
    expect(await store.readTarget(), const SmbTarget());
    expect((await store.readLedger()).records, isEmpty);
    expect(await store.readPassword(), isNull);
  });
}
