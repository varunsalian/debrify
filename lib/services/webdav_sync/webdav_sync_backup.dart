import 'dart:convert';
import 'dart:typed_data';

import '../../models/webdav_item.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_models.dart';

/// Portable connection intent, never an engine journal or a device identity.
/// Stored inside the integrity-checked, unencrypted local backup manifest.
final class WebDavSyncBackup {
  const WebDavSyncBackup({
    this.connection,
    this.profileIds = const {},
    this.resourceIds = const {},
  });

  final Map<String, dynamic>? connection;
  final Map<String, String> profileIds;
  final Map<String, String> resourceIds;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'connection': connection,
    'profileIds': profileIds,
    'resourceIds': resourceIds,
  };

  factory WebDavSyncBackup.fromJson(Map<String, dynamic> value) {
    if (value['version'] != 1) {
      throw const FormatException('Unsupported sync backup');
    }
    Map<String, String> ids(String key) {
      final raw = value[key];
      if (raw is! Map ||
          raw.length > 4096 ||
          raw.values.any((v) => v is! String) ||
          raw.keys.any((v) => v is! String)) {
        throw const FormatException('Invalid sync backup identities');
      }
      if (raw.values.toSet().length != raw.length ||
          raw.keys.any(
            (key) => !RegExp(
              r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$',
            ).hasMatch(key as String),
          )) {
        throw const FormatException('Invalid sync backup identity mapping');
      }
      return Map<String, String>.from(raw);
    }

    final raw = value['connection'];
    if (raw != null) {
      if (raw is! Map<String, dynamic> ||
          raw['enabled'] is! bool ||
          [
            'endpoint',
            'folder',
            'name',
            'username',
            'password',
            'passphrase',
            'authority',
          ].any((key) => raw[key] is! String)) {
        throw const FormatException('Invalid sync backup connection');
      }
      if (utf8.encode(jsonEncode(raw)).length > 128 * 1024) {
        throw const FormatException('Sync backup connection is too large');
      }
      WebDavSyncFolderLocation(
        endpoint: raw['endpoint'],
        folderPath: raw['folder'],
        serverName: raw['name'],
      );
      final hash = raw['authorityHash'];
      if (hash != null &&
          (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash))) {
        throw const FormatException('Invalid sync backup authority pin');
      }
      final bytes = base64Decode(raw['authority'] as String);
      if (bytes.isEmpty || bytes.length > WebDavSyncAuthorityFile.maxBytes) {
        throw const FormatException('Invalid sync backup authority');
      }
    }
    return WebDavSyncBackup(
      connection: raw == null ? null : Map<String, dynamic>.from(raw as Map),
      profileIds: ids('profileIds'),
      resourceIds: ids('resourceIds'),
    );
  }

  Future<void> validate() async {
    final value = connection;
    if (value == null) return;
    await WebDavSyncCodec().openPinnedAuthority(
      base64Decode(value['authority'] as String),
      value['passphrase'] as String,
      runInBackground: true,
    );
  }

  static Future<WebDavSyncBackup> capture({
    required WebDavSyncBindingStore store,
    required WebDavSyncEngineStateRepository states,
    required Map<String, String> profilesByLocalId,
    required Map<String, String> resourcesByLocalId,
  }) async {
    final snapshot = await store.load();
    var binding = snapshot.activeBinding ?? snapshot.stagedBinding;
    final staged = snapshot.stagedBinding;
    if (snapshot.activeBinding != null &&
        staged != null &&
        (staged.lifecycle == WebDavSyncLifecycle.awaitingAdoption ||
            staged.lifecycle == WebDavSyncLifecycle.active)) {
      // A candidate is not the effective account merely because setup pinned
      // its root. Completed handoff maps point at the new local profile IDs.
      try {
        final stagedState = await states.load(staged.namespaceId);
        if (stagedState.hasAuthenticatedMaps) {
          final activeState = await states.load(
            snapshot.activeBinding!.namespaceId,
          );
          final oldIds =
              activeState.circleToLocalProfiles?.values.toSet() ?? <String>{};
          if (stagedState.circleToLocalProfiles!.values.any(
            (id) =>
                profilesByLocalId.containsKey(id) &&
                (staged.lifecycle == WebDavSyncLifecycle.active ||
                    !oldIds.contains(id)),
          )) {
            binding = staged;
          }
        }
      } on WebDavSyncEngineStateMissingException {
        // The working account remains the only proven authority.
      }
    }
    final namespace = binding == null ? null : snapshot.namespaceFor(binding);
    if (binding == null || namespace == null || namespace.markerBytes == null) {
      return const WebDavSyncBackup();
    }
    final secrets = await store.readSecrets(binding);
    WebDavSyncEngineState state;
    try {
      state = await states.load(namespace.id);
    } on WebDavSyncEngineStateMissingException {
      state = const WebDavSyncEngineState();
    }
    Map<String, String> project(
      Map<String, String>? source,
      Map<String, String> ids,
    ) => {
      for (final entry in (source ?? <String, String>{}).entries)
        if (ids[entry.value] != null) entry.key: ids[entry.value]!,
    };
    final authority = Uint8List.fromList(namespace.markerBytes!);
    return WebDavSyncBackup(
      connection: {
        'endpoint': binding.location.endpoint.toString(),
        'folder': binding.location.folderPath,
        'name': binding.location.serverName,
        'username': secrets.username,
        'password': secrets.password,
        'passphrase': secrets.syncPassphrase,
        'authority': base64Encode(authority),
        'authorityHash': namespace.pinnedAuthorityHash,
        'enabled':
            !WebDavSyncBindingStore.logoutPending(snapshot) &&
            (binding.lifecycle == WebDavSyncLifecycle.active ||
                binding.lifecycle == WebDavSyncLifecycle.awaitingAdoption),
      },
      profileIds: project(
        state.circleToLocalProfiles ??
            _restoredIds(namespace, 'backupRestoreProfileIds'),
        profilesByLocalId,
      ),
      resourceIds: project(
        state.circleToLocalResources ??
            _restoredIds(namespace, 'backupRestoreResourceIds'),
        resourcesByLocalId,
      ),
    );
  }

  static Map<String, String>? _restoredIds(
    WebDavSyncNamespace namespace,
    String key,
  ) {
    final value = namespace.values[key];
    return value is Map ? Map<String, String>.from(value) : null;
  }

  WebDavConfig get config => WebDavConfig(
    id: 'restored-sync',
    name: connection!['name'],
    baseUrl: connection!['endpoint'],
    username: connection!['username'],
    password: connection!['password'],
  );
}
