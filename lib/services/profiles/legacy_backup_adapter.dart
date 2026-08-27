import '../backup_restore_service.dart';
import 'portable_profile_package.dart';

/// Normalizes the last non-profile plain-v1 / encrypted-v2 inner payload into
/// the same package consumed by file and remote restore.
class LegacyBackupAdapter {
  LegacyBackupAdapter._();

  static PortableProfilePackage adapt(Map<String, dynamic> payload) {
    final version = (payload['version'] as num?)?.toInt();
    if (version != BackupRestoreService.payloadVersion) {
      throw const FormatException('Unsupported legacy backup payload');
    }
    final resources = <Map<String, dynamic>>[];
    // Legacy backups have always been forward-compatible maps. Unknown
    // top-level fields belong to newer optional features and are ignored.
    final createdAtValue = payload['createdAt'];
    if (createdAtValue != null &&
        (createdAtValue is! String ||
            DateTime.tryParse(createdAtValue) == null)) {
      throw const FormatException('Legacy backup timestamp is malformed');
    }
    String requiredString(
      Map<String, dynamic> map,
      String field,
      String resource,
    ) {
      final value = map[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Legacy $resource field $field is malformed');
      }
      return value.trim();
    }

    String requiredText(
      Map<String, dynamic> map,
      String field,
      String resource,
    ) {
      final value = map[field];
      if (value is! String) {
        throw FormatException('Legacy $resource field $field is malformed');
      }
      return value;
    }

    void scalar(
      String field,
      String type,
      String label,
      Map<String, dynamic> Function(Object value) secret,
    ) {
      if (!payload.containsKey(field)) return;
      final value = payload[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Legacy credential $field is malformed');
      }
      final config = secret(value);
      config.removeWhere((_, item) => item == null || item == '');
      if (config.isEmpty) return;
      resources.add(<String, dynamic>{
        'backupId': 'legacy-$field',
        'type': type,
        'label': label,
        'owned': true,
        'publicConfig': <String, dynamic>{'schemaVersion': 1},
        'secretConfig': config,
      });
    }

    scalar(
      'realDebridApiKey',
      'realDebrid',
      'Real-Debrid',
      (value) => <String, dynamic>{'apiKey': value},
    );
    scalar(
      'torboxApiKey',
      'torbox',
      'TorBox',
      (value) => <String, dynamic>{'apiKey': value},
    );
    scalar(
      'premiumizeApiKey',
      'premiumize',
      'Premiumize',
      (value) => <String, dynamic>{'apiKey': value},
    );
    scalar(
      'allDebridApiKey',
      'allDebrid',
      'AllDebrid',
      (value) => <String, dynamic>{'apiKey': value},
    );
    void mapResource(
      String field,
      String type,
      String label,
      void Function(Map<String, dynamic>) validate,
    ) {
      if (!payload.containsKey(field)) return;
      final value = payload[field];
      if (value is! Map || value.isEmpty) {
        throw FormatException('Legacy credential $field is malformed');
      }
      final map = Map<String, dynamic>.from(value);
      validate(map);
      resources.add(<String, dynamic>{
        'backupId': 'legacy-$field',
        'type': type,
        'label': label,
        'owned': true,
        'publicConfig': <String, dynamic>{'schemaVersion': 1},
        'secretConfig': map,
      });
    }

    mapResource('pikpak', 'pikpak', 'PikPak', (map) {
      requiredString(map, 'email', 'PikPak');
    });
    mapResource('trakt', 'trakt', 'Trakt', (map) {
      requiredString(map, 'access_token', 'Trakt');
      requiredString(map, 'refresh_token', 'Trakt');
    });
    mapResource('simkl', 'simkl', 'Simkl', (map) {
      requiredString(map, 'access_token', 'Simkl');
    });

    final webDav = payload['webDavServers'];
    if (payload.containsKey('webDavServers') && webDav is! List) {
      throw const FormatException('Legacy WebDAV collection is malformed');
    }
    if (webDav is List) {
      for (var index = 0; index < webDav.length; index++) {
        final value = webDav[index];
        if (value is! Map) {
          throw FormatException('Legacy WebDAV entry $index is malformed');
        }
        final map = Map<String, dynamic>.from(value);
        requiredString(map, 'baseUrl', 'WebDAV entry $index');
        final name = map['name'];
        if (name != null && name is! String) {
          throw FormatException('Legacy WebDAV entry $index has bad name');
        }
        resources.add(<String, dynamic>{
          'backupId': 'legacy-webdav-$index',
          'type': 'webDav',
          'label': (name as String?)?.trim().isNotEmpty == true
              ? name!.trim()
              : 'WebDAV',
          'owned': true,
          'publicConfig': <String, dynamic>{'schemaVersion': 1},
          'secretConfig': map,
        });
      }
    }
    final indexers = payload['indexerManagers'];
    if (payload.containsKey('indexerManagers') && indexers is! List) {
      throw const FormatException('Legacy indexer collection is malformed');
    }
    if (indexers is List) {
      for (var index = 0; index < indexers.length; index++) {
        final value = indexers[index];
        if (value is! Map) {
          throw FormatException('Legacy indexer entry $index is malformed');
        }
        final map = Map<String, dynamic>.from(value);
        requiredString(map, 'base_url', 'indexer entry $index');
        requiredString(map, 'api_key', 'indexer entry $index');
        final managerType = map['type'];
        if (managerType != 'jackett' && managerType != 'prowlarr') {
          throw FormatException('Legacy indexer entry $index has bad type');
        }
        final name = map['name'];
        if (name != null && name is! String) {
          throw FormatException('Legacy indexer entry $index has bad name');
        }
        resources.add(<String, dynamic>{
          'backupId': 'legacy-indexer-$index',
          'type': map['type'] == 'prowlarr' ? 'prowlarr' : 'jackett',
          'label': (name as String?)?.trim().isNotEmpty == true
              ? name!.trim()
              : 'Indexer',
          'owned': true,
          'publicConfig': <String, dynamic>{'schemaVersion': 1},
          'secretConfig': map,
        });
      }
    }
    final playlists = payload['iptvPlaylists'];
    if (payload.containsKey('iptvPlaylists') && playlists is! List) {
      throw const FormatException('Legacy IPTV collection is malformed');
    }
    if (playlists is List) {
      for (var index = 0; index < playlists.length; index++) {
        final value = playlists[index];
        if (value is! Map) {
          throw FormatException('Legacy IPTV entry $index is malformed');
        }
        final map = Map<String, dynamic>.from(value);
        requiredString(map, 'id', 'IPTV entry $index');
        final rawName = map['name'];
        if (rawName != null && rawName is! String) {
          throw FormatException('Legacy IPTV entry $index has bad name');
        }
        final addedAt = requiredString(map, 'addedAt', 'IPTV entry $index');
        if (DateTime.tryParse(addedAt) == null) {
          throw FormatException('Legacy IPTV entry $index has bad timestamp');
        }
        final rawServerUrl = map['serverUrl'];
        if (rawServerUrl != null && rawServerUrl is! String) {
          throw FormatException('Legacy IPTV entry $index has bad server URL');
        }
        final xtream = (rawServerUrl as String?)?.trim().isNotEmpty == true;
        if (xtream) {
          requiredString(map, 'serverUrl', 'IPTV entry $index');
          requiredText(map, 'url', 'IPTV entry $index');
          requiredString(map, 'username', 'IPTV entry $index');
          requiredText(map, 'password', 'IPTV entry $index');
        } else {
          requiredString(map, 'url', 'IPTV entry $index');
        }
        final name = (rawName as String?)?.trim();
        map['name'] = name?.isNotEmpty == true ? name : 'IPTV';
        resources.add(<String, dynamic>{
          'backupId': 'legacy-iptv-$index',
          'type': xtream ? 'iptvXtream' : 'iptvM3u',
          'label': name?.isNotEmpty == true ? name : 'IPTV',
          'owned': true,
          'publicConfig': <String, dynamic>{
            'schemaVersion': 1,
            'playlistName': name?.isNotEmpty == true ? name : 'IPTV',
            'providerKind': xtream ? 'xtream' : 'm3u',
          },
          'secretConfig': map,
        });
      }
    }

    List<dynamic> requiredList(String field) {
      if (!payload.containsKey(field)) return const <dynamic>[];
      final value = payload[field];
      if (value is! List) {
        throw FormatException('Legacy $field collection is malformed');
      }
      return value;
    }

    void validateChannel(Object? value, String location) {
      if (value is! Map) {
        throw FormatException('Legacy $location is malformed');
      }
      final map = Map<String, dynamic>.from(value);
      requiredString(map, 'url', location);
      for (final field in const <String>[
        'name',
        'logoUrl',
        'group',
        'contentType',
        'playlistId',
        'playlistKey',
      ]) {
        if (map[field] != null && map[field] is! String) {
          throw FormatException('Legacy $location field $field is malformed');
        }
      }
      final headers = map['httpHeaders'];
      if (headers != null &&
          (headers is! Map ||
              headers.entries.any(
                (entry) => entry.key is! String || entry.value is! String,
              ))) {
        throw FormatException('Legacy $location headers are malformed');
      }
    }

    final searchEngines = requiredList('searchEngineIds');
    for (var index = 0; index < searchEngines.length; index++) {
      final value = searchEngines[index];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Legacy search engine entry $index is malformed');
      }
    }
    final favorites = requiredList('iptvFavorites');
    for (var index = 0; index < favorites.length; index++) {
      validateChannel(favorites[index], 'IPTV favorite entry $index');
    }
    final lists = requiredList('iptvLists');
    var listChannelCount = 0;
    for (var index = 0; index < lists.length; index++) {
      final value = lists[index];
      if (value is! Map) {
        throw FormatException('Legacy IPTV list entry $index is malformed');
      }
      final map = Map<String, dynamic>.from(value);
      final rawName = map['name'];
      if (rawName != null && rawName is! String) {
        throw FormatException('Legacy IPTV list entry $index has bad name');
      }
      final name = (rawName as String?)?.trim();
      map['name'] = name?.isNotEmpty == true
          ? name
          : 'Imported list ${index + 1}';
      final channels = map['channels'];
      if (channels is! List) {
        throw FormatException(
          'Legacy IPTV list entry $index channels are malformed',
        );
      }
      listChannelCount += channels.length;
      for (
        var channelIndex = 0;
        channelIndex < channels.length;
        channelIndex++
      ) {
        validateChannel(
          channels[channelIndex],
          'IPTV list $index channel $channelIndex',
        );
      }
    }

    final addons = payload['addonManifestUrls'];
    if (payload.containsKey('addonManifestUrls') && addons is! List) {
      throw const FormatException('Legacy addon collection is malformed');
    }
    if (addons is List) {
      for (var index = 0; index < addons.length; index++) {
        final value = addons[index];
        if (value is! String || value.trim().isEmpty) {
          throw FormatException('Legacy addon entry $index is malformed');
        }
        resources.add(<String, dynamic>{
          'backupId': 'legacy-stremio-$index',
          'type': 'stremioAddon',
          'label': 'Stremio addon',
          'owned': true,
          'publicConfig': const <String, dynamic>{
            'schemaVersion': 1,
            'addonName': 'Stremio addon',
            'contentKinds': <String>[],
          },
          'secretConfig': <String, dynamic>{'manifestUrl': value.trim()},
        });
      }
    }

    final legacyFollowUp = Map<String, dynamic>.from(payload);
    if (lists.isNotEmpty) {
      legacyFollowUp['iptvLists'] = <Map<String, dynamic>>[
        for (var index = 0; index < lists.length; index++)
          <String, dynamic>{
            ...Map<String, dynamic>.from(lists[index] as Map),
            'name':
                ((lists[index] as Map)['name'] as String?)?.trim().isNotEmpty ==
                    true
                ? ((lists[index] as Map)['name'] as String).trim()
                : 'Imported list ${index + 1}',
          },
      ];
    }
    for (final key in const <String>[
      'realDebridApiKey',
      'torboxApiKey',
      'premiumizeApiKey',
      'allDebridApiKey',
      'pikpak',
      'trakt',
      'simkl',
      'webDavServers',
      'indexerManagers',
      'iptvPlaylists',
      'addonManifestUrls',
    ]) {
      legacyFollowUp.remove(key);
    }

    return PortableProfilePackage(
      mode: 'legacySingleProfile',
      createdAt:
          DateTime.tryParse(payload['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      profiles: const <Map<String, dynamic>>[
        <String, dynamic>{
          'backupId': 'legacy-profile',
          'preferencesSection': 'legacy-preferences',
        },
      ],
      resources: resources,
      sections: <String, dynamic>{
        'legacy-preferences': const <String, dynamic>{
          'schemaVersion': 1,
          'recordCount': 0,
          'values': <String, dynamic>{},
        },
        // Only non-resource legacy categories remain here. The restore
        // coordinator applies them into the invisible shadow generation.
        'legacyFollowUp': legacyFollowUp,
        'legacyInventory': <String, dynamic>{
          'schemaVersion': 1,
          'resourceRecords': resources.length,
          'searchEngineRecords': searchEngines.length,
          'iptvFavoriteRecords': favorites.length,
          'iptvListRecords': lists.length,
          'iptvListChannelRecords': listChannelCount,
        },
      },
      omissions: const <String, dynamic>{
        'profiles': true,
        'historyAndResume': true,
        'downloadsAndRecordings': true,
        'jobsAndSchedules': true,
        'pins': true,
        'remotePairings': true,
        'localFiles': true,
      },
    );
  }
}
