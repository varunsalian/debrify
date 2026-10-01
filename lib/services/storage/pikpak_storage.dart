import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';

final class PikpakStorage {
  const PikpakStorage._();
  static const String _pikpakHiddenFromNavKey = 'pikpak_hidden_from_nav';
  // Shared within lib/services/storage/.
  static const String pikpakPostTorrentActionKey = 'pikpak_post_torrent_action';

  // PikPak API settings
  static const String _pikpakEnabledKey = 'pikpak_enabled';
  static const String _pikpakEmailKey = 'pikpak_email';
  static const String _pikpakPasswordKey = 'pikpak_password';
  static const String _pikpakAccessTokenKey = 'pikpak_access_token';
  static const String _pikpakRefreshTokenKey = 'pikpak_refresh_token';
  static const String _pikpakDeviceIdKey = 'pikpak_device_id';
  static const String _pikpakCaptchaTokenKey = 'pikpak_captcha_token';
  static const String _pikpakUserIdKey = 'pikpak_user_id';
  static const String _pikpakShowVideosOnlyKey = 'pikpak_show_videos_only';
  static const String _pikpakIgnoreSmallVideosKey = 'pikpak_ignore_small_videos';
  static const String _pikpakRestrictedFolderIdKey = 'pikpak_restricted_folder_id';
  static const String _pikpakRestrictedFolderNameKey = 'pikpak_restricted_folder_name';
  static const String _pikpakTorrentsFolderIdKey = 'pikpak_torrents_folder_id';
  static const String _pikpakTvFolderIdKey = 'pikpak_tv_folder_id';

  // PikPak post-torrent action methods
  static Future<String> getPikPakPostTorrentAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(pikpakPostTorrentActionKey) ?? 'choose';
  }

  static Future<void> savePikPakPostTorrentAction(String action) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(pikpakPostTorrentActionKey, action);
  }

  // PikPak API Settings
  static Future<bool> getPikPakEnabled({bool Function()? canContinue}) async {
    if (canContinue != null) {
      return ProfileRuntime.withoutCapturedScope(() async {
        if (!canContinue()) return false;
        final prefs = await ProfilePreferences.instance();
        if (!canContinue() || !(prefs.getBool(_pikpakEnabledKey) ?? false)) {
          return false;
        }
        final configured = await ProviderCredentialStorage.credentialConfigured(
          _pikpakEmailKey,
          () => getPikPakEmail(canContinue: canContinue),
        );
        return canContinue() && configured;
      });
    }
    final prefs = await ProfilePreferences.instance();
    if (!(prefs.getBool(_pikpakEnabledKey) ?? false)) return false;
    return ProviderCredentialStorage.credentialConfigured(_pikpakEmailKey, () => getPikPakEmail());
  }

  static Future<bool> hasPikPakCredential() =>
      ProviderCredentialStorage.credentialConfigured(_pikpakEmailKey, () => getPikPakEmail());

  static Future<void> setPikPakEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakEnabledKey, value);
  }

  static Future<String?> getPikPakEmail({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue != null) {
      return ProviderCredentialStorage.readCurrentProviderCredential(
        _pikpakEmailKey,
        canContinue,
        forRemoteTransfer: forRemoteTransfer,
      );
    }
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _pikpakEmailKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakEmailKey);
  }

  static Future<void> setPikPakEmail(String email) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakEmailKey, email);
  }

  static Future<String?> getPikPakPassword() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakPasswordKey);
  }

  static Future<void> setPikPakPassword(String password) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakPasswordKey, password);
  }

  static Future<String?> getPikPakAccessToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakAccessTokenKey);
  }

  static Future<void> setPikPakAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakAccessTokenKey, token);
  }

  static Future<String?> getPikPakRefreshToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakRefreshTokenKey);
  }

  static Future<void> setPikPakRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakRefreshTokenKey, token);
  }

  static Future<void> clearPikPakAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_pikpakEmailKey)) {
      await prefs.remove(_pikpakEmailKey);
      await prefs.remove(_pikpakPasswordKey);
      await prefs.remove(_pikpakAccessTokenKey);
      await prefs.remove(_pikpakRefreshTokenKey);
      await prefs.remove(_pikpakDeviceIdKey);
      await prefs.remove(_pikpakCaptchaTokenKey);
      await prefs.remove(_pikpakUserIdKey);
    }
    await prefs.setBool(_pikpakEnabledKey, false);

    // Also clear restricted folder settings and cached subfolder IDs
    await clearPikPakRestrictedFolder();
    await clearPikPakSubfolderCaches();
    await clearPikPakHiddenFromNav();
  }

  // PikPak Device ID and Captcha Token
  static Future<void> setPikPakDeviceId(String deviceId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakDeviceIdKey, deviceId);
  }

  static Future<String?> getPikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakDeviceIdKey);
  }

  static Future<void> deletePikPakDeviceId() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakDeviceIdKey);
  }

  static Future<void> setPikPakCaptchaToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakCaptchaTokenKey, token);
  }

  static Future<String?> getPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakCaptchaTokenKey);
  }

  static Future<void> clearPikPakCaptchaToken() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakCaptchaTokenKey);
  }

  static Future<void> setPikPakUserId(String userId) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _pikpakUserIdKey, userId);
  }

  static Future<String?> getPikPakUserId() async {
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _pikpakUserIdKey);
  }

  // PikPak Show Videos Only
  static Future<bool> getPikPakShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakShowVideosOnlyKey) ?? true; // Default to true
  }

  static Future<void> setPikPakShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakShowVideosOnlyKey, value);
  }

  // PikPak Ignore Small Videos (under 100MB)
  static Future<bool> getPikPakIgnoreSmallVideos() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakIgnoreSmallVideosKey) ?? true; // Default to true
  }

  static Future<void> setPikPakIgnoreSmallVideos(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakIgnoreSmallVideosKey, value);
  }

  // PikPak Restricted Folder
  static Future<String?> getPikPakRestrictedFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderIdKey);
  }

  static Future<String?> getPikPakRestrictedFolderName() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakRestrictedFolderNameKey);
  }

  static Future<void> setPikPakRestrictedFolder(
    String? folderId,
    String? folderName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (folderId == null) {
      await prefs.remove(_pikpakRestrictedFolderIdKey);
      await prefs.remove(_pikpakRestrictedFolderNameKey);
    } else {
      await prefs.setString(_pikpakRestrictedFolderIdKey, folderId);
      if (folderName != null) {
        await prefs.setString(_pikpakRestrictedFolderNameKey, folderName);
      }
    }
  }

  static Future<void> clearPikPakRestrictedFolder() async {
    await setPikPakRestrictedFolder(null, null);
    // Also clear subfolder caches when restriction changes
    await clearPikPakSubfolderCaches();
  }

  // PikPak Subfolder ID caching (for debrify-torrents and debrify-tv folders)
  static Future<String?> getPikPakTorrentsFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTorrentsFolderIdKey);
  }

  static Future<void> setPikPakTorrentsFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTorrentsFolderIdKey, folderId);
  }

  static Future<String?> getPikPakTvFolderId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_pikpakTvFolderIdKey);
  }

  static Future<void> setPikPakTvFolderId(String folderId) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_pikpakTvFolderIdKey, folderId);
  }

  static Future<void> clearPikPakSubfolderCaches() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakTorrentsFolderIdKey);
    await prefs.remove(_pikpakTvFolderIdKey);
  }

  // PikPak Hidden from Navigation
  static Future<bool> getPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_pikpakHiddenFromNavKey) ?? false;
  }

  static Future<void> setPikPakHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_pikpakHiddenFromNavKey, hidden);
  }

  static Future<void> clearPikPakHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_pikpakHiddenFromNavKey);
  }
}
