import 'dart:convert';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_collection_resource_facade.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';

final class IptvPlaylistStorage {
  const IptvPlaylistStorage._();

  // IPTV settings
  static const String _iptvPlaylistsKey = 'iptv_playlists';
  static const String _iptvDefaultPlaylistKey = 'iptv_default_playlist';

  // IPTV Playlist Settings

  /// Credential-bearing fields of a stored playlist. Encrypted field-level
  /// rather than sealing the whole element: `content` can be a multi-megabyte
  /// raw M3U body and this getter sits on hot paths, so blob-level AES would
  /// cost real time on TV hardware for data that arrived as a plaintext file
  /// the user chose. Residual: URLs embedded inside a file-imported `content`
  /// body stay plaintext — accepted.
  static const List<String> _iptvPlaylistSecretFields = [
    'url', 'serverUrl', 'username', 'password', 'epgUrl', //
  ];

  /// Restores the `url` key the legacy→profile migration erased.
  ///
  /// An Xtream provider legitimately stores `url: ''` — its endpoint is
  /// [IptvPlaylist.serverUrl]. The migration's shared resource writer stripped
  /// every empty value before sealing, so an Xtream resource migrated by an
  /// affected build carries no `url` key at all, and `IptvPlaylist.fromJson`
  /// threw on the required cast. That took out the ENTIRE playlist list — and
  /// with it the IPTV page — rather than the one provider.
  ///
  /// Fixing the migration cannot help these devices: migration is a one-way
  /// door that never re-runs. Repairing on read is what brings them back, and
  /// it keeps working for anyone who migrated on an affected build and updates
  /// later.
  ///
  /// TWO provider kinds legitimately carry an empty `url`, and both are
  /// repaired: an Xtream login (endpoint in `serverUrl`) and a playlist
  /// imported from a file (body in `content` — see the IPTV settings page,
  /// which writes `url: ''` for exactly that reason). Neither field is
  /// stripped by the migration, so either one identifies a record whose empty
  /// `url` was real rather than missing.
  ///
  /// Still deliberately narrow: a row with none of the three is genuinely
  /// malformed and keeps throwing, because papering over that would turn real
  /// corruption into a silent blank provider.
  static Map<String, dynamic> _repairMigratedIptvRow(Map<String, dynamic> row) {
    if (row['url'] != null) return row;
    if (!_hasText(row['serverUrl']) && !_hasText(row['content'])) return row;
    return <String, dynamic>{...row, 'url': ''};
  }

  static bool _hasText(Object? value) => value is String && value.trim().isNotEmpty;

  /// Get all saved IPTV playlists
  static Future<List<IptvPlaylist>> getIptvPlaylists({
    bool forSettings = true,
    bool forRemoteTransfer = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final rows = await ProfileCollectionResourceFacade.read(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        forSettings: forSettings,
        forRemoteTransfer: forRemoteTransfer,
      );
      return rows.map(_repairMigratedIptvRow).map(IptvPlaylist.fromJson).toList(growable: false);
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = prefs.getStringList(_iptvPlaylistsKey) ?? [];
    var legacySeen = false;
    var anyDropped = false;
    final playlists = <IptvPlaylist>[];
    for (final json in jsonList) {
      try {
        final opened = await SecretVault.openFields(
          Map<String, dynamic>.from(jsonDecode(json) as Map),
          _iptvPlaylistSecretFields,
        );
        if (opened.wasLegacy) legacySeen = true;
        // A playlist whose url failed to decrypt throws in fromJson and is
        // dropped here — same signed-out semantics as the standalone keys.
        playlists.add(IptvPlaylist.fromJson(opened.map));
      } catch (e) {
        // Skip malformed entries FOR THIS READ only.
        anyDropped = true;
      }
    }
    // Migrate lazily, but never off a lossy read: rewriting while an entry
    // failed (possibly a transient vault-key hiccup) would turn a one-launch
    // read error into permanent deletion. A later clean read migrates.
    if (legacySeen && !anyDropped) {
      await setIptvPlaylists(playlists);
    }
    return playlists;
  }

  /// Save IPTV playlists.
  ///
  /// Virtual playlists (Favorites, custom lists, Continue watching, Stremio
  /// addon shelves) are dropped here rather than trusted not to arrive: the
  /// page's own list holds real and virtual entries side by side, and a
  /// virtual one that reached the preference would be restored AND injected
  /// on the next load — two entries with the same id, where id-only equality
  /// makes lookups resolve the stale copy.
  static Future<void> setIptvPlaylists(
    List<IptvPlaylist> playlists, {
    bool revokeBorrowers = false,
  }) async {
    if (ProfileCollectionResourceFacade.active) {
      final stored = playlists.where((playlist) => !playlist.isVirtual);
      await ProfileCollectionResourceFacade.replace(
        types: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
          ConnectionResourceType.iptvXtream,
        },
        feature: ProfileFeature.iptv,
        items: <ResourceCollectionItem>[
          for (final playlist in stored)
            ResourceCollectionItem(
              type: playlist.isXtreamCodes ? ConnectionResourceType.iptvXtream : ConnectionResourceType.iptvM3u,
              label: playlist.name,
              publicConfig: <String, dynamic>{
                'playlistName': playlist.name,
                'providerKind': playlist.isXtreamCodes ? 'xtream' : 'm3u',
              },
              secretConfig: playlist.toJson(),
              sourceResourceId: playlist.connectionResourceId,
            ),
        ],
        revokeBorrowers: revokeBorrowers,
      );
      return;
    }
    final prefs = await ProfilePreferences.instance();
    final jsonList = <String>[];
    for (final p in playlists.where((p) => !p.isVirtual)) {
      jsonList.add(
        jsonEncode(
          await SecretVault.sealFields(p.toJson(), _iptvPlaylistSecretFields),
        ),
      );
    }
    await prefs.setStringList(_iptvPlaylistsKey, jsonList);
  }

  /// Persists an IPTV collection and returns the authoritative records.
  ///
  /// In profile mode a collection write can mint or rotate connection
  /// resources, so the caller's input objects are deliberately not execution
  /// capabilities. UI code that keeps using those objects would have no
  /// resource ID for a new playlist, or a stale revision for an existing one.
  static Future<List<IptvPlaylist>> setIptvPlaylistsAndReload(
    List<IptvPlaylist> playlists, {
    required bool forSettings,
    bool revokeBorrowers = false,
  }) async {
    final expectedScope = ProfileCollectionResourceFacade.active ? ProfileRuntime.scope.value : null;
    await setIptvPlaylists(playlists, revokeBorrowers: revokeBorrowers);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active || ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while saving IPTV playlists');
    }
    final saved = await getIptvPlaylists(forSettings: forSettings);
    if (expectedScope != null &&
        (!ProfileCollectionResourceFacade.active || ProfileRuntime.scope.value != expectedScope)) {
      throw StateError('Profile changed while loading IPTV playlists');
    }
    return saved;
  }

  /// Get default IPTV playlist ID
  static Future<String?> getIptvDefaultPlaylist() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_iptvDefaultPlaylistKey);
  }

  /// Set default IPTV playlist ID
  static Future<void> setIptvDefaultPlaylist(String? playlistId) async {
    final prefs = await ProfilePreferences.instance();
    if (playlistId == null || playlistId.isEmpty) {
      await prefs.remove(_iptvDefaultPlaylistKey);
    } else {
      await prefs.setString(_iptvDefaultPlaylistKey, playlistId);
    }
  }
}
