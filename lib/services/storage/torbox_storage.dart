import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';

final class TorboxStorage {
  const TorboxStorage._();
  static const String _torboxApiKey = 'torbox_api_key';
  static const String _torboxCacheCheckPref = 'torbox_check_cache_before_search';
  // Shared within lib/services/storage/.
  static const String torboxIntegrationEnabledKey = 'torbox_integration_enabled';
  // Shared within lib/services/storage/.
  static const String torboxHiddenFromNavKey = 'torbox_hidden_from_nav';
  // Shared within lib/services/storage/.
  static const String torboxPostTorrentActionKey = 'torbox_post_torrent_action';

  // Torbox API key helpers
  static Future<String?> getTorboxApiKey({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue != null) {
      return ProviderCredentialStorage.readCurrentProviderCredential(
        _torboxApiKey,
        canContinue,
        forRemoteTransfer: forRemoteTransfer,
      );
    }
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _torboxApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _torboxApiKey);
  }

  static Future<bool> hasTorboxCredential() =>
      ProviderCredentialStorage.credentialConfigured(_torboxApiKey, () => getTorboxApiKey());

  static Future<void> saveTorboxApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _torboxApiKey, apiKey);
  }

  static Future<void> deleteTorboxApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_torboxApiKey)) {
      await prefs.remove(_torboxApiKey);
    }
  }

  static Future<bool> getTorboxCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torboxCacheCheckPref) ?? false;
  }

  static Future<void> setTorboxCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torboxCacheCheckPref, enabled);
  }

  static Future<bool> getTorboxIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(torboxIntegrationEnabledKey) ?? true;
  }

  static Future<void> setTorboxIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(torboxIntegrationEnabledKey, enabled);
  }

  static Future<bool> getTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(torboxHiddenFromNavKey) ?? false;
  }

  static Future<void> setTorboxHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(torboxHiddenFromNavKey, hidden);
  }

  static Future<void> clearTorboxHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(torboxHiddenFromNavKey);
  }

  // TorBox post-torrent action methods
  static Future<String> getTorboxPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(torboxPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> saveTorboxPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(torboxPostTorrentActionKey, action);
  }
}
