import 'dart:convert';
import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:flutter/foundation.dart';

final class TorrentProviderStorage {
  const TorrentProviderStorage._();

  // Default Torrent Provider Settings
  // Values: 'none' (ask every time), 'torbox', 'debrid', 'pikpak'
  // Shared within lib/services/storage/.
  static const String defaultTorrentProviderKey = 'default_torrent_provider_v1';
  static const String _indexerManagerConfigsKey = 'indexer_manager_configs_v1';

  /// Clear torrent engine toggles and limits
  static Future<void> clearAllTorrentEngineSettings() async {
    final prefs = await ProfilePreferences.instance();
    final keys = prefs.getKeys().where(
      (key) =>
          (key.startsWith('engine_') && !key.startsWith('engine_tv_')) ||
          (key.startsWith('default_') && key.endsWith('_enabled')) ||
          (key.startsWith('max_') && key.endsWith('_results')),
    );
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
  }

  // Default Torrent Provider methods
  // Returns: 'none' (ask every time), 'torbox', 'debrid', or 'pikpak'
  static Future<String> getDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(defaultTorrentProviderKey) ?? 'none';
  }

  static Future<void> setDefaultTorrentProvider(
    String provider, {
    bool Function()? canContinue,
  }) async {
    if (canContinue == null) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setString(defaultTorrentProviderKey, provider);
      return;
    }
    await ProfileRuntime.withoutCapturedScope(() async {
      if (!canContinue()) return;
      final prefs = await ProfilePreferences.instance();
      if (!canContinue()) return;
      await ProfilePreferences.synchronizeExternalMutation(() async {
        // Waiting for a profile snapshot may retire the picker. Check here,
        // with no intervening await before the nested preference setter.
        if (!canContinue()) return;
        await prefs.setString(defaultTorrentProviderKey, provider);
      }, marksMutation: false);
    });
  }

  static Future<void> clearDefaultTorrentProvider() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(defaultTorrentProviderKey);
  }

  static Future<List<IndexerManagerConfig>> getIndexerManagerConfigs({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = await SecretVault.getStringList(
      prefs,
      _indexerManagerConfigsKey,
    );
    return rawList
        .map((raw) {
          try {
            return IndexerManagerConfig.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            );
          } catch (e) {
            debugPrint('Error loading indexer manager config: $e');
            return null;
          }
        })
        .whereType<IndexerManagerConfig>()
        .toList();
  }

  static Future<List<IndexerManagerConfig>> setIndexerManagerConfigs(
    List<IndexerManagerConfig> configs,
  ) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.jackett,
          ConnectionResourceType.prowlarr,
        },
        feature: ProfileFeature.torrentSearch,
        items: <ResourceCollectionItem>[
          for (final config in configs)
            ResourceCollectionItem(
              type: config.type == IndexerManagerType.prowlarr
                  ? ConnectionResourceType.prowlarr
                  : ConnectionResourceType.jackett,
              label: config.displayName,
              publicConfig: <String, dynamic>{
                'managerName': config.displayName,
              },
              secretConfig: config.toJson(),
              sourceResourceId: config.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      return rows.map(IndexerManagerConfig.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final rawList = configs.map((config) => jsonEncode(config.toJson())).toList();
    await SecretVault.setStringList(prefs, _indexerManagerConfigsKey, rawList);
    return List<IndexerManagerConfig>.unmodifiable(configs);
  }
}
