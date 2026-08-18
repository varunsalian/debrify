import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/iptv_playlist.dart';
import 'iptv_media_store.dart';
import 'storage_service.dart';

/// Serializes the IPTV side of a user's setup — providers, Favorites, and
/// custom channel lists — into plain JSON, and merges that JSON back into a
/// device.
///
/// Shared by the two transports that move a setup between devices: the backup
/// file ([BackupRestoreService]) and the phone→TV Remote transfer. Keeping one
/// builder means the two can't drift into carrying different data, which is
/// how WebDAV and the indexer managers ended up in the backup and in "Transfer
/// Everything" but not in "Send Setup to TV".
///
/// The three categories are deliberately separate payloads rather than one
/// blob: a user re-pointing a TV at the same panel usually wants the sources
/// only, and the Remote flow sends each selected category as its own UDP
/// command. They do have an ordering dependency though — memberships name the
/// playlist they came from, so senders must apply providers first.
abstract final class IptvTransferPayload {
  static final Object _providerIdOverridesKey = Object();

  static Future<T> withProviderIdOverrides<T>(
    Map<String, String> providerIdsByFingerprint,
    Future<T> Function() body,
  ) => runZoned(
    body,
    zoneValues: <Object, Object>{
      _providerIdOverridesKey: Map<String, String>.unmodifiable(
        providerIdsByFingerprint,
      ),
    },
  );

  static String providerFingerprintFromJson(Map<String, dynamic> json) =>
      _fingerprint(IptvPlaylist.fromJson(json));
  // ── Providers ────────────────────────────────────────────────────────────

  /// The user's transferable IPTV providers, as `IptvPlaylist.toJson()` maps.
  ///
  /// Two kinds are left out:
  ///
  /// * **Virtual** playlists (Favorites, custom lists, Continue watching,
  ///   addon shelves) — rebuilt from their backing store on the receiving
  ///   device, so a persisted copy would come back twice under one id.
  /// * **File-imported** playlists — their whole definition is the raw M3U
  ///   text, which runs to megabytes: too big for a UDP transfer, and big
  ///   enough in a backup file to push it past the size a restore will read.
  ///   Re-import the file on the other device instead. Their starred channels
  ///   still travel: a membership carries its own playable URL and headers.
  static Future<List<Map<String, dynamic>>> buildPlaylists({
    bool forRemoteTransfer = false,
  }) async {
    final playlists = await StorageService.getIptvPlaylists(
      forSettings: !forRemoteTransfer,
      forRemoteTransfer: forRemoteTransfer,
    );
    return [
      for (final playlist in playlists)
        if (!playlist.isVirtual && !playlist.isLocalFile)
          playlist.toTransferJson(),
    ];
  }

  /// How many providers are configured, split into the ones [buildPlaylists]
  /// carries and the file-imported ones it leaves behind — so a confirm
  /// dialog can say what won't be included rather than quietly dropping it.
  static Future<({int transferable, int fileImported})> countPlaylists() async {
    final playlists = await StorageService.getIptvPlaylists();
    final real = playlists.where((p) => !p.isVirtual).toList();
    final fileImported = real.where((p) => p.isLocalFile).length;
    return (
      transferable: real.length - fileImported,
      fileImported: fileImported,
    );
  }

  /// Merge providers into this device, keeping whatever is already here.
  ///
  /// De-duped by what actually identifies a provider to its panel, not by id:
  /// the same Xtream server added on two devices gets two different generated
  /// ids, and matching on those would import a duplicate every time.
  ///
  /// An incoming provider keeps its own id, because Favorites and list
  /// memberships name the playlist they came from — rewriting the id here
  /// would orphan every channel that arrives with it.
  static Future<IptvImportCounts> applyPlaylists(List<dynamic> entries) async {
    final counts = IptvImportCounts();
    try {
      final existing = await StorageService.getIptvPlaylists();
      final existingKeys = <String>{for (final p in existing) _fingerprint(p)};
      final existingIds = <String>{for (final p in existing) p.id};
      final merged = List<IptvPlaylist>.from(existing);

      for (final raw in entries) {
        if (raw is! Map) {
          counts.failed++;
          continue;
        }
        try {
          final playlist = IptvPlaylist.fromTransferJson(
            Map<String, dynamic>.from(raw),
          );
          // A url is what makes a non-Xtream provider fetchable, so an entry
          // without one is junk. An Xtream provider legitimately has none —
          // it is stored with an empty url and identified by server +
          // account — so it must not be judged by that rule, or every Xtream
          // panel is dropped on arrival.
          if (playlist.isVirtual ||
              (!playlist.isXtreamCodes && playlist.url.trim().isEmpty)) {
            counts.failed++;
            continue;
          }
          if (existingKeys.contains(_fingerprint(playlist))) {
            counts.alreadyPresent++;
            continue;
          }
          // An id collision with a *different* provider would make one of them
          // unreachable (playlist equality is id-only). Skip rather than
          // silently shadow the one already here.
          if (existingIds.contains(playlist.id)) {
            counts.failed++;
            continue;
          }
          merged.add(playlist);
          existingKeys.add(_fingerprint(playlist));
          existingIds.add(playlist.id);
          counts.imported++;
        } catch (_) {
          debugPrint('IptvTransferPayload: playlist entry failed');
          counts.failed++;
        }
      }

      if (counts.imported > 0) {
        await StorageService.setIptvPlaylists(merged);
      }
    } catch (_) {
      counts.error = 'IPTV playlist import failed';
    }
    return counts;
  }

  /// What identifies a provider to its panel: the Xtream server + account for
  /// Xtream entries, the normalized URL otherwise. File-imported playlists
  /// have no meaningful URL, so they fall back to their name.
  static String _fingerprint(IptvPlaylist playlist) {
    if (playlist.isXtreamCodes) {
      final server = _normalizeUrl(playlist.serverUrl ?? '');
      return 'xtream|$server|${playlist.username ?? ''}';
    }
    if (playlist.isLocalFile) {
      return 'file|${playlist.name.trim().toLowerCase()}';
    }
    return 'url|${_normalizeUrl(playlist.url)}';
  }

  static String _normalizeUrl(String url) =>
      url.trim().toLowerCase().replaceFirst(RegExp(r'/+$'), '');

  // ── Favorites and custom lists ───────────────────────────────────────────

  /// The starred channels of the built-in Favorites list.
  static Future<List<Map<String, dynamic>>> buildFavorites({
    bool forRemoteTransfer = false,
  }) async {
    final fingerprints = await _fingerprintsById(
      forRemoteTransfer: forRemoteTransfer,
    );
    return _channelEntries(
      await IptvMediaStore.listChannels(IptvMediaStore.favoritesListId),
      fingerprints,
      restrictToKnownOrigins: forRemoteTransfer,
    );
  }

  /// Every user-created list with its channels. Favorites is excluded — it
  /// travels as its own category so it can be selected independently.
  static Future<List<Map<String, dynamic>>> buildCustomLists({
    bool forRemoteTransfer = false,
  }) async {
    final fingerprints = await _fingerprintsById(
      forRemoteTransfer: forRemoteTransfer,
    );
    final metas = await IptvMediaStore.lists();
    final out = <Map<String, dynamic>>[];
    for (final meta in metas) {
      if (meta.isBuiltin) continue;
      out.add(<String, dynamic>{
        'name': meta.name,
        'position': meta.position,
        'channels': _channelEntries(
          await IptvMediaStore.listChannels(meta.id),
          fingerprints,
          restrictToKnownOrigins: forRemoteTransfer,
        ),
      });
    }
    return out;
  }

  /// Local playlist id → the fingerprint that identifies it to its panel.
  static Future<Map<String, String>> _fingerprintsById({
    required bool forRemoteTransfer,
  }) async {
    final playlists = await StorageService.getIptvPlaylists(
      forSettings: !forRemoteTransfer,
      forRemoteTransfer: forRemoteTransfer,
    );
    return {
      for (final playlist in playlists)
        if (!playlist.isVirtual) playlist.id: _fingerprint(playlist),
    };
  }

  /// Field naming the provider a membership came from, in a form that means
  /// the same thing on both devices (unlike the generated id).
  static const String _originKey = 'playlistKey';

  /// Flatten a store map (url → presentation metadata) into a JSON array,
  /// folding the url in as a field so the entry is self-describing.
  ///
  /// Everything a list view needs to *play* a channel without re-fetching its
  /// provider is carried: a channel with a custom User-Agent that lost its
  /// headers would show up in the list and then refuse to play.
  ///
  /// The origin provider travels as a fingerprint alongside the raw
  /// `playlistId`. The id is generated per device, so when the receiver
  /// already knows this panel under an id of its own, the fingerprint is what
  /// lets the membership re-bind to it — an id that resolves to nothing there
  /// would cost the channel its Xtream credentials on resume, and leave it
  /// behind when that provider is later deleted.
  static List<Map<String, dynamic>> _channelEntries(
    Map<String, Map<String, dynamic>> channels,
    Map<String, String> fingerprintsById, {
    bool restrictToKnownOrigins = false,
  }) {
    return [
      for (final entry in channels.entries)
        if (!restrictToKnownOrigins ||
            entry.value['playlistId'] == null ||
            fingerprintsById.containsKey(entry.value['playlistId']))
          <String, dynamic>{
            'url': entry.key,
            ...entry.value,
            if (fingerprintsById[entry.value['playlistId']] != null)
              _originKey: fingerprintsById[entry.value['playlistId']],
          },
    ];
  }

  /// Merge starred channels into the built-in Favorites list.
  static Future<IptvImportCounts> applyFavorites(List<dynamic> entries) async {
    return _applyChannels(IptvMediaStore.favoritesListId, entries);
  }

  /// Merge custom lists into this device.
  ///
  /// A list is matched to an existing one by name (case-insensitively), so
  /// re-running a transfer tops up "Sports" instead of creating "Sports" a
  /// second time. Unmatched names are created.
  static Future<IptvImportCounts> applyCustomLists(
    List<dynamic> entries,
  ) async {
    final counts = IptvImportCounts();
    try {
      final existing = await IptvMediaStore.lists();
      final byName = <String, String>{
        for (final meta in existing)
          if (!meta.isBuiltin) meta.name.trim().toLowerCase(): meta.id,
      };

      for (final raw in entries) {
        if (raw is! Map) {
          counts.failed++;
          continue;
        }
        final name = (raw['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) {
          counts.failed++;
          continue;
        }
        try {
          var listId = byName[name.toLowerCase()];
          if (listId == null) {
            listId = await IptvMediaStore.createList(name);
            byName[name.toLowerCase()] = listId;
            counts.imported++;
          } else {
            counts.alreadyPresent++;
          }
          final channels = raw['channels'];
          if (channels is List) {
            final channelCounts = await _applyChannels(listId, channels);
            counts.channelsImported += channelCounts.channelsImported;
            counts.channelsAlreadyPresent +=
                channelCounts.channelsAlreadyPresent;
            counts.failed += channelCounts.failed;
          }
        } catch (_) {
          debugPrint('IptvTransferPayload: list import failed');
          counts.failed++;
        }
      }
    } catch (_) {
      counts.error = 'IPTV list import failed';
    }
    return counts;
  }

  /// Write channel entries into [listId], skipping ones already there.
  ///
  /// "Already there" is judged canonically, matching how the store itself
  /// compares membership — a row saved before the Xtream `/live/` URL fix is
  /// the same channel as the one arriving now, and must not be added twice.
  static Future<IptvImportCounts> _applyChannels(
    String listId,
    List<dynamic> entries,
  ) async {
    final counts = IptvImportCounts();
    try {
      final existing = await IptvMediaStore.listChannels(listId);
      final existingKeys = <String>{
        for (final url in existing.keys)
          IptvMediaStore.canonicalChannelKey(url),
      };
      // The sender's provider ids mean nothing here. Anything whose panel this
      // device already knows is re-pointed at the local id for it.
      final localIdByFingerprint = <String, String>{
        for (final playlist in await StorageService.getIptvPlaylists())
          if (!playlist.isVirtual) _fingerprint(playlist): playlist.id,
        ...?Zone.current[_providerIdOverridesKey] as Map<String, String>?,
      };

      for (final raw in entries) {
        if (raw is! Map) {
          counts.failed++;
          continue;
        }
        final url = (raw['url'] as String?)?.trim() ?? '';
        if (url.isEmpty) {
          counts.failed++;
          continue;
        }
        final key = IptvMediaStore.canonicalChannelKey(url);
        if (existingKeys.contains(key)) {
          counts.channelsAlreadyPresent++;
          continue;
        }
        try {
          await IptvMediaStore.setChannelInList(
            listId,
            url,
            true,
            channelName: raw['name'] as String?,
            logoUrl: raw['logoUrl'] as String?,
            group: raw['group'] as String?,
            channelNumber: (raw['channelNumber'] as num?)?.toInt(),
            contentType: raw['contentType'] as String?,
            duration: (raw['duration'] as num?)?.toInt(),
            httpHeaders: _headers(raw['httpHeaders']),
            // Modern payloads carry playlistKey (a stable fingerprint); old
            // v1/v2 payloads carried only the sender-local playlistId. The
            // restore coordinator supplies overrides for both forms while
            // staged providers are still outside the visible resource graph.
            playlistId:
                localIdByFingerprint[raw[_originKey]] ??
                localIdByFingerprint[raw['playlistId']] ??
                raw['playlistId'] as String?,
          );
          existingKeys.add(key);
          counts.channelsImported++;
        } catch (_) {
          debugPrint('IptvTransferPayload: channel import failed');
          counts.failed++;
        }
      }
    } catch (_) {
      counts.error = 'IPTV channel import failed';
    }
    return counts;
  }

  static Map<String, String>? _headers(Object? raw) {
    if (raw is! Map) return null;
    final headers = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is String && value is String) headers[key] = value;
    }
    return headers.isEmpty ? null : headers;
  }

  // ── Counting helpers for confirm dialogs ─────────────────────────────────

  /// Total channels across every entry of a custom-list payload.
  static int countListChannels(List<dynamic> entries) {
    var total = 0;
    for (final raw in entries) {
      if (raw is! Map) continue;
      final channels = raw['channels'];
      if (channels is List) total += channels.length;
    }
    return total;
  }
}

/// What an apply pass did. Providers and lists report through
/// [imported]/[alreadyPresent]; the channels inside a list report through the
/// channel counters, so "3 lists, 120 channels" stays expressible.
class IptvImportCounts {
  int imported = 0;
  int alreadyPresent = 0;
  int channelsImported = 0;
  int channelsAlreadyPresent = 0;
  int failed = 0;
  String? error;

  bool get isEmpty =>
      imported == 0 &&
      alreadyPresent == 0 &&
      channelsImported == 0 &&
      channelsAlreadyPresent == 0 &&
      failed == 0;
}
