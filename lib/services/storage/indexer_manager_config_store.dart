import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/indexer_manager_config.dart';
import '../../models/profiles/connection_resource.dart';
import '../../models/profiles/profile_policy.dart';
import '../profiles/connection_resource_service.dart';
import '../profiles/profile_collection_resource_facade.dart';
import '../profiles/profile_preferences.dart';
import '../secret_vault.dart';

/// Indexer model adaptation and legacy storage. Canonical resource authority
/// remains in ProfileCollectionResourceFacade and its services.
class IndexerManagerConfigStore {
  IndexerManagerConfigStore._();

  static const String _indexerManagerConfigsKey = 'indexer_manager_configs_v1';

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
    final rawList = configs
        .map((config) => jsonEncode(config.toJson()))
        .toList();
    await SecretVault.setStringList(prefs, _indexerManagerConfigsKey, rawList);
    return List<IndexerManagerConfig>.unmodifiable(configs);
  }

}
