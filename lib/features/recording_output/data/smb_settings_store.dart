// Per-profile persistence for the SMB recording upload.
//
// Profile-owned like the recordings it uploads: each profile has its own
// share, credentials and upload history, and none of it is device-global
// (the isolation suite forbids device-wide credentials). ProfilePreferences
// captures the active profile when opened and refuses writes once another
// profile has taken over. The password is sealed at rest (SecretVault by
// default), never stored as plaintext.

import 'package:debrify/features/recording_output/application/smb_contracts.dart';
import 'package:debrify/features/recording_output/models/smb_target.dart';
import 'package:debrify/features/recording_output/models/smb_upload_models.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';

/// Seals a plaintext secret for storage.
typedef SecretSeal = Future<String> Function(String plaintext);

/// Opens a stored secret; null means absent or unreadable.
typedef SecretOpen = Future<String?> Function(String? stored);

/// Reads and writes the active profile's SMB recording keys.
///
/// This is the coordinator's [SmbUploadSettings] boundary: the uploader never
/// touches SharedPreferences itself.
final class SmbSettingsStore implements SmbUploadSettings {
  SmbSettingsStore({SecretSeal? seal, SecretOpen? open})
    : _seal = seal ?? SecretVault.seal,
      _open = open ?? SecretVault.open;

  /// Profile key holding the encoded [SmbTarget].
  static const targetKey = 'recording_smb_target_v1';

  /// Profile key holding the sealed share password.
  static const passwordKey = 'recording_smb_password_v1';

  /// Profile key holding the encoded upload ledger.
  static const ledgerKey = 'recording_smb_uploads_v1';

  final SecretSeal _seal;
  final SecretOpen _open;

  @override
  Future<SmbTarget> readTarget() async {
    final prefs = await ProfilePreferences.instance();
    return SmbTarget.decode(prefs.getString(targetKey));
  }

  Future<void> writeTarget(SmbTarget target) async {
    final prefs = await ProfilePreferences.instance();
    if (!await prefs.setString(targetKey, target.encode())) {
      throw StateError('The SMB settings could not be saved');
    }
  }

  @override
  Future<String?> readPassword() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getString(passwordKey);
    if (stored == null) return null;
    final password = await _open(stored);
    // A stored but unreadable password must not log on as '' (a wrong
    // password, and a lockout risk on the NAS): the pass reports it instead.
    if (password == null) {
      throw StateError(
        'The saved SMB password could not be read; enter it again',
      );
    }
    return password;
  }

  /// null or '' removes the key; otherwise stores seal(password).
  Future<void> writePassword(String? password) async {
    final sealed = password == null || password.isEmpty
        ? null
        : await _seal(password);
    final prefs = await ProfilePreferences.instance();
    final saved = sealed == null
        ? await prefs.remove(passwordKey)
        : await prefs.setString(passwordKey, sealed);
    if (!saved) throw StateError('The SMB password could not be saved');
  }

  @override
  Future<SmbUploadLedger> readLedger() async {
    final prefs = await ProfilePreferences.instance();
    return SmbUploadLedger.decode(prefs.getString(ledgerKey));
  }

  /// Profile writes are budgeted; a refused write is an error.
  @override
  Future<void> writeLedger(SmbUploadLedger ledger) async {
    final prefs = await ProfilePreferences.instance();
    // A refused write would forget uploads and copy them again next pass.
    if (!await prefs.setString(ledgerKey, ledger.encode())) {
      throw StateError('The upload history could not be saved');
    }
  }
}
