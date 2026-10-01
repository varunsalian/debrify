import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';

final class WebdavStorage {
  const WebdavStorage._();
  // Shared within lib/services/storage/.
  static const String webDavEnabledKey = 'webdav_enabled';
  // Shared within lib/services/storage/.
  static const String webDavHiddenFromNavKey = 'webdav_hidden_from_nav';
  // Shared within lib/services/storage/.
  static const String webDavBaseUrlKey = 'webdav_base_url';
  // Shared within lib/services/storage/.
  static const String webDavUsernameKey = 'webdav_username';
  // Shared within lib/services/storage/.
  static const String webDavPasswordKey = 'webdav_password';
  static const String _webDavShowVideosOnlyKey = 'webdav_show_videos_only';

  // WebDAV Settings
  static Future<bool> getWebDavEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(webDavEnabledKey) ?? false;
  }

  static Future<void> setWebDavEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(webDavEnabledKey, value);
  }

  static Future<bool> getWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(webDavHiddenFromNavKey) ?? false;
  }

  static Future<void> setWebDavHiddenFromNav(bool hidden) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(webDavHiddenFromNavKey, hidden);
  }

  static Future<void> clearWebDavHiddenFromNav() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(webDavHiddenFromNavKey);
  }

  static Future<String?> getWebDavBaseUrl() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await WebdavServerStorage.getSelectedWebDavServer();
    return selected?.baseUrl ?? await SecretVault.getString(prefs, webDavBaseUrlKey);
  }

  static Future<void> setWebDavBaseUrl(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await WebdavServerStorage.getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await WebdavServerStorage.getWebDavServers(forSettings: false);
        await WebdavServerStorage.saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: value,
                    username: item.username,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, webDavBaseUrlKey, value);
  }

  static Future<String?> getWebDavUsername() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await WebdavServerStorage.getSelectedWebDavServer();
    return selected?.username ?? await SecretVault.getString(prefs, webDavUsernameKey);
  }

  static Future<void> setWebDavUsername(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await WebdavServerStorage.getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await WebdavServerStorage.getWebDavServers(forSettings: false);
        await WebdavServerStorage.saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: value,
                    password: item.password,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, webDavUsernameKey, value);
  }

  static Future<String?> getWebDavPassword() async {
    final prefs = await ProfilePreferences.instance();
    final selected = await WebdavServerStorage.getSelectedWebDavServer();
    return selected?.password ?? await SecretVault.getString(prefs, webDavPasswordKey);
  }

  static Future<void> setWebDavPassword(String value) async {
    if (ProfileCollectionResourceFacade.active) {
      final selected = await WebdavServerStorage.getSelectedWebDavServer(forSettings: false);
      if (selected != null) {
        if (selected.connectionReadOnly) {
          throw const ResourceAuthorizationException(
            'Shared WebDAV connections cannot be edited',
          );
        }
        final all = await WebdavServerStorage.getWebDavServers(forSettings: false);
        await WebdavServerStorage.saveWebDavServers([
          for (final item in all)
            item.id == selected.id
                ? WebDavConfig(
                    id: item.id,
                    name: item.name,
                    baseUrl: item.baseUrl,
                    username: item.username,
                    password: value,
                    connectionResourceId: item.connectionResourceId,
                    connectionResourceRevision: item.connectionResourceRevision,
                    connectionReadOnly: item.connectionReadOnly,
                    credentialsRedacted: item.credentialsRedacted,
                  )
                : item,
        ]);
      }
      return;
    }
    final prefs = await ProfilePreferences.instance();
    await SecretVault.setString(prefs, webDavPasswordKey, value);
  }

  static Future<bool> getWebDavShowVideosOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_webDavShowVideosOnlyKey) ?? true;
  }

  static Future<void> setWebDavShowVideosOnly(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_webDavShowVideosOnlyKey, value);
  }

  static Future<void> clearWebDav({
    ProfileFeature feature = ProfileFeature.cloud,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{ConnectionResourceType.webDav},
        feature: feature,
        items: const <ResourceCollectionItem>[],
      );
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(webDavBaseUrlKey);
    await prefs.remove(webDavUsernameKey);
    await prefs.remove(webDavPasswordKey);
    await prefs.remove(webDavHiddenFromNavKey);
    await prefs.remove(WebdavServerStorage.webDavServersKey);
    await prefs.remove(WebdavServerStorage.webDavSelectedServerIdKey);
    await prefs.setBool(webDavEnabledKey, false);
  }
}
