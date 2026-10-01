import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';

final class PremiumizeStorage {
  const PremiumizeStorage._();
  static const String _premiumizeApiKey = 'premiumize_api_key';
  // Shared within lib/services/storage/.
  static const String premiumizeIntegrationEnabledKey = 'premiumize_integration_enabled';
  // Shared within lib/services/storage/.
  static const String premiumizePostTorrentActionKey = 'premiumize_post_torrent_action';
  static const String _premiumizeCacheCheckPref = 'premiumize_check_cache_before_search';
  // Shared within lib/services/storage/.
  static const String premiumizeHiddenFromNavKey = 'premiumize_hidden_from_nav';

  // Premiumize API key helpers
  static Future<String?> getPremiumizeApiKey({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue != null) {
      return ProviderCredentialStorage.readCurrentProviderCredential(
        _premiumizeApiKey,
        canContinue,
        forRemoteTransfer: forRemoteTransfer,
      );
    }
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _premiumizeApiKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _premiumizeApiKey);
  }

  static Future<bool> hasPremiumizeCredential() =>
      ProviderCredentialStorage.credentialConfigured(_premiumizeApiKey, () => getPremiumizeApiKey());

  static Future<void> savePremiumizeApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _premiumizeApiKey, apiKey);
  }

  static Future<void> deletePremiumizeApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_premiumizeApiKey)) {
      await prefs.remove(_premiumizeApiKey);
    }
  }

  static Future<bool> getPremiumizeIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(premiumizeIntegrationEnabledKey) ?? true;
  }

  static Future<void> setPremiumizeIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(premiumizeIntegrationEnabledKey, enabled);
  }

  static Future<bool> getPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(premiumizeHiddenFromNavKey) ?? false;
  }

  static Future<void> setPremiumizeHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(premiumizeHiddenFromNavKey, hidden);
  }

  static Future<void> clearPremiumizeHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(premiumizeHiddenFromNavKey);
  }

  // Premiumize post-torrent action methods
  static Future<String> getPremiumizePostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(premiumizePostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePremiumizePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(premiumizePostTorrentActionKey, action);
  }

  static Future<bool> getPremiumizeCacheCheckEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_premiumizeCacheCheckPref) ?? false;
  }

  static Future<void> setPremiumizeCacheCheckEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_premiumizeCacheCheckPref, enabled);
  }
}
