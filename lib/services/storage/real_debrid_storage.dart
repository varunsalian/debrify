import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';

final class RealDebridStorage {
  const RealDebridStorage._();

  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _rdEndpointKey = 'real_debrid_endpoint';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  // Shared within lib/services/storage/.
  static const String realDebridIntegrationEnabledKey = 'real_debrid_integration_enabled';
  // Shared within lib/services/storage/.
  static const String realDebridHiddenFromNavKey = 'real_debrid_hidden_from_nav';
  static const String _rdSkipBlockedTorrentsKey = 'rd_skip_blocked_torrents';
  // Shared within lib/services/storage/.
  static const String postTorrentActionKey = 'post_torrent_action';

  static Future<String?> getApiKey({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue != null) {
      return ProviderCredentialStorage.readCurrentProviderCredential(
        _apiKeyKey,
        canContinue,
        forRemoteTransfer: forRemoteTransfer,
      );
    }
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _apiKeyKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _apiKeyKey);
  }

  static Future<bool> hasRealDebridCredential() =>
      ProviderCredentialStorage.credentialConfigured(_apiKeyKey, () => getApiKey());

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _apiKeyKey, apiKey);
  }

  static Future<void> deleteApiKey() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_apiKeyKey)) {
      await prefs.remove(_apiKeyKey);
    }
  }

  // Real-Debrid endpoint preference (for fallback to backup endpoint)
  static Future<String> getRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    // Default to primary endpoint
    return prefs.getString(_rdEndpointKey) ?? 'https://api.real-debrid.com/rest/1.0';
  }

  static Future<void> saveRdEndpoint(String endpoint) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_rdEndpointKey, endpoint);
  }

  static Future<void> deleteRdEndpoint() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_rdEndpointKey);
  }

  static Future<bool> getRealDebridIntegrationEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(realDebridIntegrationEnabledKey) ?? true;
  }

  static Future<void> setRealDebridIntegrationEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(realDebridIntegrationEnabledKey, enabled);
  }

  static Future<bool> getRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(realDebridHiddenFromNavKey) ?? false;
  }

  static Future<void> setRealDebridHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(realDebridHiddenFromNavKey, hidden);
  }

  static Future<void> clearRealDebridHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(realDebridHiddenFromNavKey);
  }

  static Future<bool> getRdSkipBlockedTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_rdSkipBlockedTorrentsKey) ?? true;
  }

  static Future<void> setRdSkipBlockedTorrents(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_rdSkipBlockedTorrentsKey, enabled);
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_fileSelectionKey) ?? 'smart'; // Default to smart selection
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_fileSelectionKey, selection);
  }

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(postTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(postTorrentActionKey, action);
  }
}
