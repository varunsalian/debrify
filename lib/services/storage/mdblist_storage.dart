import 'dart:convert';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/profiles/profile_credential_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/provider_credential_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';

final class MdblistStorage {
  const MdblistStorage._();

  // MDBList settings. Auth is a single API key (from mdblist.com/preferences),
  // so there's no token/expiry — just the key and a cached display username.
  static const String _mdblistApiKeyKey = 'mdblist_api_key';
  static const String _mdblistUsernameKey = 'mdblist_username';

  // MDBList API key + cached username helpers
  static Future<String?> getMdblistApiKey({
    bool forRemoteTransfer = false,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return null;
    if (forRemoteTransfer) {
      final credential = await ProfileCredentialFacade.readForRemoteTransfer(
        _mdblistApiKeyKey,
      );
      if (canContinue?.call() == false) return null;
      if (credential.handled) return credential.value;
    }
    final prefs = await ProfilePreferences.instance();
    if (canContinue?.call() == false) return null;
    return SecretVault.getString(
      prefs,
      _mdblistApiKeyKey,
      canContinue: canContinue,
    );
  }

  static Future<bool> hasMdblistCredential({bool Function()? canContinue}) =>
      ProviderCredentialStorage.credentialConfigured(
        _mdblistApiKeyKey,
        () => getMdblistApiKey(),
        canContinue: canContinue,
      );

  static Future<void> saveMdblistApiKey(String apiKey) async {
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, _mdblistApiKeyKey, apiKey);
  }

  static Future<String?> getMdblistUsername() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_mdblistUsernameKey);
  }

  static Future<void> setMdblistUsername(String? username) async {
    final prefs = await ProfilePreferences.instance();
    if (username == null || username.isEmpty) {
      await prefs.remove(_mdblistUsernameKey);
    } else {
      await prefs.setString(_mdblistUsernameKey, username);
    }
  }

  /// Clears all stored MDBList auth (key + cached username).
  static Future<void> clearMdblistAuth() async {
    final prefs = await ProfilePreferences.instance();
    if (!await ProfileCredentialFacade.disconnect(_mdblistApiKeyKey)) {
      await prefs.remove(_mdblistApiKeyKey);
    }
    await prefs.remove(_mdblistUsernameKey);
    await prefs.remove(_mdblistSavedClonesKey);
    await prefs.remove(_mdblistSyncCheckpointKey);
    await TrackingSourceStorage.fallbackDisconnectedProgressSource(TrackingSource.mdblist);
  }

  // Maps a source MDBList list id -> the id of the static list we CLONED it
  // into on the user's account (the "Save" action). Lets the Save button know a
  // list is already saved and which clone to delete on un-save. JSON object of
  // {"<sourceId>": clonedId}.
  static const String _mdblistSavedClonesKey = 'mdblist_saved_clones';

  static Future<Map<int, int>> getMdblistSavedClones() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSavedClonesKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, int>{};
      decoded.forEach((k, v) {
        final sid = int.tryParse(k.toString());
        final cid = v is int ? v : (v is num ? v.toInt() : null);
        if (sid != null && cid != null) out[sid] = cid;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<void> setMdblistSavedClone(int sourceId, int clonedId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map[sourceId] = clonedId;
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  static Future<void> removeMdblistSavedClone(int sourceId) async {
    final prefs = await ProfilePreferences.instance();
    final map = await getMdblistSavedClones();
    map.remove(sourceId);
    await prefs.setString(
      _mdblistSavedClonesKey,
      jsonEncode(map.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  /// Retire the old clone-as-like UI bookkeeping. Remote lists are deliberately
  /// untouched: an old clone is now simply a normal user-owned list.
  static Future<void> retireMdblistSavedCloneMarkers() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_mdblistSavedClonesKey);
  }

  static const String _mdblistSyncCheckpointKey = 'mdblist_sync_checkpoint_v1';

  static Future<Map<String, dynamic>?> getMdblistSyncCheckpoint() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_mdblistSyncCheckpointKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setMdblistSyncCheckpoint(
    Map<String, dynamic>? value,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_mdblistSyncCheckpointKey);
    } else {
      await prefs.setString(_mdblistSyncCheckpointKey, jsonEncode(value));
    }
  }

  static Future<void> setMdblistSyncCatalogItems(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('mdblist_sync_catalog_items', value);
  }

  static Future<bool> getMdblistSyncCatalogItems() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('mdblist_sync_catalog_items') ?? false;
  }
}
