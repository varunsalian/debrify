import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';

final class SimklStorage {
  const SimklStorage._();

  // Simkl settings. No refresh-token/expiry keys — PIN-issued Simkl tokens
  // don't expire (see SimklService).
  static const String _simklAccessTokenKey = 'simkl_access_token';
  static const String _simklUsernameKey = 'simkl_username';

  static Future<void> setSimklSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('simkl_sync_catalog_items', value);
  }

  static Future<bool> getSimklSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('simkl_sync_catalog_items') ?? false;
  }

  static Future<String?> getSimklAccessToken({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return null;
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _simklAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(
      prefs,
      _simklAccessTokenKey,
      canContinue: canContinue,
    );
  }

  static Future<bool> hasSimklCredential({bool Function()? canContinue}) =>
      ProviderCredentialStorage.credentialConfigured(
        _simklAccessTokenKey,
        () => getSimklAccessToken(),
        canContinue: canContinue,
      );

  static Future<void> setSimklAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _simklAccessTokenKey, token);
  }

  static Future<String?> getSimklUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_simklUsernameKey);
  }

  static Future<void> setSimklUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_simklUsernameKey, username);
  }

  static Future<void> clearSimklAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_simklAccessTokenKey)) {
      await prefs.remove(_simklAccessTokenKey);
    }
    await prefs.remove(_simklUsernameKey);
    await TrackingSourceStorage.fallbackDisconnectedProgressSource(TrackingSource.simkl);
  }
}
