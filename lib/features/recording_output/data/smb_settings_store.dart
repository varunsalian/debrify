// Device-wide persistence for the SMB recording upload.
//
// Goes through DevicePreferences, the reviewed unscoped store: all three keys
// are registered in DevicePreferences.allowedKeys and both profile device-key
// lists. The password is sealed at rest (SecretVault by default), never
// stored as plaintext.

import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';

/// Seals a plaintext secret for storage.
typedef SecretSeal = Future<String> Function(String plaintext);

/// Opens a stored secret; null means absent or unreadable.
typedef SecretOpen = Future<String?> Function(String? stored);

/// Reads and writes the three device-wide SMB recording keys.
///
/// This is the coordinator's [SmbUploadSettings] boundary: the uploader never
/// touches SharedPreferences itself.
final class SmbSettingsStore implements SmbUploadSettings {
  SmbSettingsStore({SecretSeal? seal, SecretOpen? open})
    : _seal = seal ?? SecretVault.seal,
      _open = open ?? SecretVault.open;

  /// Device-wide key holding the encoded [SmbTarget].
  static const targetKey = 'recording_smb_target_v1';

  /// Device-wide key holding the sealed share password.
  static const passwordKey = 'recording_smb_password_v1';

  /// Device-wide key holding the encoded upload ledger.
  static const ledgerKey = 'recording_smb_uploads_v1';

  final SecretSeal _seal;
  final SecretOpen _open;

  @override
  Future<SmbTarget> readTarget() async {
    final prefs = await DevicePreferences.instance();
    return SmbTarget.decode(prefs.getString(targetKey));
  }

  Future<void> writeTarget(SmbTarget target) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(targetKey, target.encode());
  }

  @override
  Future<String?> readPassword() async {
    final prefs = await DevicePreferences.instance();
    return _open(prefs.getString(passwordKey));
  }

  /// null or '' removes the key; otherwise stores seal(password).
  Future<void> writePassword(String? password) async {
    final prefs = await DevicePreferences.instance();
    if (password == null || password.isEmpty) {
      await prefs.remove(passwordKey);
      return;
    }
    await prefs.setString(passwordKey, await _seal(password));
  }

  @override
  Future<SmbUploadLedger> readLedger() async {
    final prefs = await DevicePreferences.instance();
    return SmbUploadLedger.decode(prefs.getString(ledgerKey));
  }

  /// The ledger is a growing collection, so it uses the budgeted write: a
  /// refused write (saturated preference store) is simply ignored.
  @override
  Future<void> writeLedger(SmbUploadLedger ledger) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBudgetedString(ledgerKey, ledger.encode());
  }
}
