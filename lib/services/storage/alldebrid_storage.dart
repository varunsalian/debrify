import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';

final class AllDebridStorage {
  const AllDebridStorage._();
  static const String _allDebridApiKey = 'alldebrid_api_key';
  // Shared within lib/services/storage/.
  static const String allDebridIntegrationEnabledKey = 'alldebrid_integration_enabled';
  // Shared within lib/services/storage/.
  static const String allDebridPostTorrentActionKey = 'alldebrid_post_torrent_action';
  // Shared within lib/services/storage/.
  static const String allDebridHiddenFromNavKey = 'alldebrid_hidden_from_nav';

  // AllDebrid API key helpers
  static Future<String?> getAllDebridApiKey({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue != null) {
      return ProviderCredentialStorage.readCurrentProviderCredential(
        _allDebridApiKey,
        canContinue,
        forRemoteTransfer: forRemoteTransfer,
      );
    }
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _allDebridApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _allDebridApiKey);
  }

  static Future<bool> hasAllDebridCredential() =>
      ProviderCredentialStorage.credentialConfigured(_allDebridApiKey, () => getAllDebridApiKey());

  static Future<void> saveAllDebridApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _allDebridApiKey, apiKey);
  }

  static Future<void> deleteAllDebridApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_allDebridApiKey)) {
      await prefs.remove(_allDebridApiKey);
    }
  }

  static Future<bool> getAllDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(allDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setAllDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(allDebridIntegrationEnabledKey, enabled);
  }

  // AllDebrid post-torrent action methods
  static Future<String> getAllDebridPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(allDebridPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveAllDebridPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(allDebridPostTorrentActionKey, action);
  }

  // AllDebrid hide-from-navigation
  static Future<bool> getAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(allDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setAllDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(allDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearAllDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(allDebridHiddenFromNavKey);
  }
}
