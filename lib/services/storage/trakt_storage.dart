import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';

final class TraktStorage {
  const TraktStorage._();

  // Trakt settings
  static const String _traktAccessTokenKey = 'trakt_access_token';
  static const String _traktRefreshTokenKey = 'trakt_refresh_token';
  static const String _traktUsernameKey = 'trakt_username';
  static const String _traktTokenExpiryKey = 'trakt_token_expiry';

  // Trakt Settings
  static Future<bool> getTraktSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('trakt_sync_catalog_items') ?? false;
  }

  static Future<void> setTraktSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('trakt_sync_catalog_items', value);
  }

  static Future<String?> getTraktAccessToken({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return null;
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktAccessTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(
      prefs,
      _traktAccessTokenKey,
      canContinue: canContinue,
    );
  }

  static Future<bool> hasTraktCredential({bool Function()? canContinue}) =>
      ProviderCredentialStorage.credentialConfigured(
        _traktAccessTokenKey,
        () => getTraktAccessToken(),
        canContinue: canContinue,
      );

  static Future<void> setTraktAccessToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktAccessTokenKey, token);
  }

  static Future<String?> getTraktRefreshToken({
    bool forRemoteTransfer = false,
  }) async {
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _traktRefreshTokenKey,
      );
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    return SecretVault.getString(prefs, _traktRefreshTokenKey);
  }

  static Future<void> setTraktRefreshToken(String token) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _traktRefreshTokenKey, token);
  }

  static Future<String?> getTraktUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_traktUsernameKey);
  }

  static Future<void> setTraktUsername(String username) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_traktUsernameKey, username);
  }

  /// Replace the token pair and its expiry as one shared session write.
  static Future<void> setTraktSession({
    required String accessToken,
    required String refreshToken,
    required int? expiryMs,
  }) async {
    if (await ProfileCredentialFacade.storeTraktSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiryMs: expiryMs,
    )) {
      return;
    }
    await setTraktAccessToken(accessToken);
    await setTraktRefreshToken(refreshToken);
    final prefs = await ProfilePreferences.instance();
    if (expiryMs == null) {
      await prefs.remove(_traktTokenExpiryKey);
    } else {
      await prefs.setInt(_traktTokenExpiryKey, expiryMs);
    }
  }

  static Future<int?> getTraktTokenExpiry() async {
    final shared = await ProfileCredentialFacade.traktSessionExpiry();
    if (shared.handled) return shared.value;
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_traktTokenExpiryKey);
  }

  static Future<void> setTraktTokenExpiry(int expiryMs) async {
    if (await ProfileCredentialFacade.setTraktSessionExpiry(expiryMs)) return;
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_traktTokenExpiryKey, expiryMs);
  }

  /// Clears the local Trakt connection first and reports whether this profile
  /// was its unshared owner. Only that disposition may revoke the upstream
  /// token; a borrower must never invalidate the account for other profiles.
  static Future<bool> clearTraktAuth() async {
    final prefs = await ProfilePreferences.instance();
    final disposition = await ProfileCredentialFacade.disconnectWithDisposition(
      _traktAccessTokenKey,
    );
    if (!disposition.handled) {
      await prefs.remove(_traktAccessTokenKey);
      await prefs.remove(_traktRefreshTokenKey);
    }
    await prefs.remove(_traktUsernameKey);
    await prefs.remove(_traktTokenExpiryKey);
    await TrackingSourceStorage.fallbackDisconnectedProgressSource(TrackingSource.trakt);
    return !disposition.handled || disposition.shouldRevokeRemote;
  }
}
