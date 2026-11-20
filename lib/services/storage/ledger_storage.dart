import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';

/// The Ledger tracker's session (placeholder name, see
/// lib/features/ledger/models/ledger_brand.dart): owned by one profile ON ONE
/// DEVICE.
///
/// Unlike Trakt/Simkl this is deliberately not a shareable or syncable
/// connection resource. Ledger revokes the whole session when a refresh
/// token that was already exchanged is presented again, so a copied token
/// pair (WebDAV sync, profile import, backup restore, another profile) would
/// eventually sign every copy out. The tokens live in profile preferences,
/// sealed with the device key, and never leave the device: their keys are
/// non-portable (ProfilePreferencePortability).
final class LedgerStorage {
  const LedgerStorage._();

  static const String _ledgerAccessTokenKey = 'ledger_access_token';
  static const String _ledgerRefreshTokenKey = 'ledger_refresh_token';
  static const String _ledgerUsernameKey = 'ledger_username';
  static const String _ledgerTokenExpiryKey = 'ledger_token_expiry';

  /// Null while Ledger is off ([kLedgerEnabled]): a stored session is unused.
  static Future<String?> getAccessToken({bool Function()? canContinue}) async {
    if (!kLedgerEnabled || canContinue?.call() == false) return null;
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(
      prefs,
      _ledgerAccessTokenKey,
      canContinue: canContinue,
    );
  }

  static Future<String?> getRefreshToken() async {
    if (!kLedgerEnabled) return null;
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _ledgerRefreshTokenKey);
  }

  static Future<bool> hasCredential({bool Function()? canContinue}) async =>
      kLedgerEnabled &&
      await ProviderCredentialStorage.credentialConfigured(
        _ledgerAccessTokenKey,
        () => getAccessToken(),
        canContinue: canContinue,
      );

  /// Replaces the token pair and its expiry together.
  static Future<void> setSession({
    required String accessToken,
    required String refreshToken,
    required int? expiryMs,
  }) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _ledgerAccessTokenKey, accessToken);
    await SecretVault.setString(prefs, _ledgerRefreshTokenKey, refreshToken);
    if (expiryMs == null) {
      await prefs.remove(_ledgerTokenExpiryKey);
    } else {
      await prefs.setInt(_ledgerTokenExpiryKey, expiryMs);
    }
  }

  static Future<int?> getTokenExpiry() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_ledgerTokenExpiryKey);
  }

  static Future<String?> getUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_ledgerUsernameKey);
  }

  static Future<void> setUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_ledgerUsernameKey, username);
  }

  /// Forgets this profile's session on this device, including its episode
  /// snapshot, so no Ledger progress outlives the connection.
  static Future<void> clearAuth() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_ledgerAccessTokenKey);
    await prefs.remove(_ledgerRefreshTokenKey);
    await prefs.remove(_ledgerUsernameKey);
    await prefs.remove(_ledgerTokenExpiryKey);
    await TrackerEpisodeProgressStorage.clearEpisodeLedgerProgress();
    await TrackingSourceStorage.fallbackDisconnectedProgressSource(
      TrackingSource.ledger,
    );
  }
}
