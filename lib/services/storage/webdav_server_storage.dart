import 'dart:convert';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/webdav_storage.dart';

final class WebdavServerStorage {
  const WebdavServerStorage._();
  // Shared within lib/services/storage/.
  static const String webDavServersKey = 'webdav_servers_v1';
  // Shared within lib/services/storage/.
  static const String webDavSelectedServerIdKey = 'webdav_selected_server_id_v1';

  static Future<List<WebDavConfig>> getWebDavServers({
    bool forSettings = true,
    bool forRemoteTransfer = false,
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows
          .map(WebDavConfig.fromJson)
          .where(
            (config) => config.baseUrl.trim().isNotEmpty || config.credentialsRedacted,
          )
          .toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final raw = await SecretVault.getString(prefs, webDavServersKey);
    final servers = <WebDavConfig>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final config = WebDavConfig.fromJson(
                item.cast<String, dynamic>(),
              );
              if (config.baseUrl.trim().isNotEmpty) servers.add(config);
            }
          }
        }
      } catch (_) {}
    }

    if (servers.isEmpty) {
      final legacyUrl = await SecretVault.getString(prefs, WebdavStorage.webDavBaseUrlKey);
      if (legacyUrl != null && legacyUrl.trim().isNotEmpty) {
        final config = WebDavConfig(
          id: 'legacy-${legacyUrl.hashCode}',
          name: Uri.tryParse(legacyUrl)?.host ?? 'WebDAV',
          baseUrl: legacyUrl,
          username: await SecretVault.getString(prefs, WebdavStorage.webDavUsernameKey) ?? '',
          password: await SecretVault.getString(prefs, WebdavStorage.webDavPasswordKey) ?? '',
        );
        servers.add(config);
        await saveWebDavServers(servers, feature: feature);
        await setSelectedWebDavServerId(config.id);
      }
    }

    return servers;
  }

  static Future<List<WebDavConfig>> saveWebDavServers(
    List<WebDavConfig> servers, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final expectedScope = ProfileRuntime.scope.value;
      if (expectedScope == null) throw StateError('No visible profile scope');
      // Capture the preference namespace before the registry mutation. If a
      // profile switch races this operation, this handle can only write the
      // initiating namespace (or fail); it can never write the new profile.
      final prefs = await ProfilePreferences.instance();
      final rows = await ProfileCollectionResourceFacade.replaceAndRead(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        items: <ResourceCollectionItem>[
          for (final server in servers)
            ResourceCollectionItem(
              type: ConnectionResourceType.webDav,
              label: server.name,
              publicConfig: <String, dynamic>{'accountLabel': server.name},
              secretConfig: server.toJson(),
              sourceResourceId: server.connectionResourceId,
            ),
        ],
        forSettings: true,
      );
      final saved = rows.map(WebDavConfig.fromJson).toList(growable: false);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV connections');
      }
      await prefs.setBool(WebdavStorage.webDavEnabledKey, saved.isNotEmpty);
      if (ProfileRuntime.scope.value != expectedScope) {
        throw StateError('Profile changed while saving WebDAV settings');
      }
      return saved;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(
      prefs,
      webDavServersKey,
      jsonEncode(servers.map((server) => server.toJson()).toList()),
    );
    await prefs.setBool(WebdavStorage.webDavEnabledKey, servers.isNotEmpty);
    return List<WebDavConfig>.unmodifiable(servers);
  }

  static Future<String?> getSelectedWebDavServerId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(webDavSelectedServerIdKey);
  }

  static Future<void> setSelectedWebDavServerId(String? id) async {
    final prefs = await ProfilePreferences.instance();
    if (id == null || id.isEmpty) {
      await prefs.remove(webDavSelectedServerIdKey);
    } else {
      await prefs.setString(webDavSelectedServerIdKey, id);
    }
  }

  static Future<WebDavConfig?> getSelectedWebDavServer({
    bool forSettings = true,
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final servers = await getWebDavServers(
      forSettings: forSettings,
      feature: feature,
    );
    if (servers.isEmpty) return null;
    final selectedId = await getSelectedWebDavServerId();
    if (selectedId != null && selectedId.isNotEmpty) {
      for (final server in servers) {
        if (server.id == selectedId) return server;
      }
    }
    await setSelectedWebDavServerId(servers.first.id);
    return servers.first;
  }

  static Future<WebDavConfig> upsertWebDavServer(
    WebDavConfig config, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active ? ProfileRuntime.scope.value : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers(feature: feature)).toList();
    final priorResourceIds = <String>{
      for (final server in servers)
        if (server.connectionResourceId != null) server.connectionResourceId!,
    };
    final index = servers.indexWhere((server) => server.id == config.id);
    var persisted = config;
    if (index == -1) {
      servers.add(persisted);
    } else {
      final source = servers[index];
      if (source.connectionReadOnly) {
        throw const ResourceAuthorizationException(
          'Shared WebDAV connections cannot be edited',
        );
      }
      persisted = WebDavConfig(
        id: config.id,
        name: config.name,
        baseUrl: config.baseUrl,
        username: config.username,
        password: config.password,
        connectionResourceId: source.connectionResourceId,
        connectionResourceRevision: source.connectionResourceRevision,
      );
      servers[index] = persisted;
    }
    final saved = await saveWebDavServers(servers, feature: feature);
    final WebDavConfig canonical;
    final sourceResourceId = persisted.connectionResourceId;
    if (sourceResourceId != null) {
      canonical = saved.singleWhere(
        (server) => server.connectionResourceId == sourceResourceId,
      );
    } else if (ProfileCollectionResourceFacade.active) {
      canonical = saved.singleWhere(
        (server) => server.connectionResourceId != null && !priorResourceIds.contains(server.connectionResourceId),
      );
    } else {
      canonical = saved.singleWhere((server) => server.id == persisted.id);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    await selectionPrefs.setString(webDavSelectedServerIdKey, canonical.id);
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while selecting a WebDAV connection');
    }
    return canonical;
  }

  static Future<void> deleteWebDavServer(
    String id, {
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active ? ProfileRuntime.scope.value : null;
    final selectionPrefs = await ProfilePreferences.instance();
    final servers = (await getWebDavServers(feature: feature)).toList();
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
    servers.removeWhere((server) => server.id == id);
    final saved = await saveWebDavServers(servers, feature: feature);
    final selected = selectionPrefs.getString(webDavSelectedServerIdKey);
    if (selected == id) {
      if (saved.isEmpty) {
        await selectionPrefs.remove(webDavSelectedServerIdKey);
      } else {
        await selectionPrefs.setString(
          webDavSelectedServerIdKey,
          saved.first.id,
        );
      }
    }
    if (saved.isEmpty) {
      await selectionPrefs.setBool(WebdavStorage.webDavHiddenFromNavKey, false);
    }
    if (expectedScope != null && ProfileRuntime.scope.value != expectedScope) {
      throw StateError('Profile changed while deleting a WebDAV connection');
    }
  }
}
