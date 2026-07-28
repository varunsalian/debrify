import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/iptv_playlist.dart';

/// A last-known-good channel catalog restored from disk.
class IptvCatalogSnapshot {
  final List<IptvChannel> channels;
  final List<String> categories;

  /// The `url-tvg` the playlist header declared at fetch time (M3U only) —
  /// carried so the EPG context can be rebuilt without a network round-trip.
  final String? epgUrl;
  final DateTime fetchedAt;

  const IptvCatalogSnapshot({
    required this.channels,
    required this.categories,
    this.epgUrl,
    required this.fetchedAt,
  });
}

/// Disk persistence for IPTV channel catalogs — one compacted JSON snapshot
/// per (source, content type), so a cold app start can render the last-known
/// list instantly and revalidate in the background instead of blocking on
/// (or dying with) the network. Serve-stale-while-revalidate; the results
/// view owns the reconcile/swap policy, this class only stores snapshots.
///
/// Only network-backed catalogs are cached: Xtream logins (live/vod/series
/// each get their own snapshot) and plain M3U URL playlists. Local files are
/// already an on-device snapshot; virtual playlists (favorites/continue/
/// Stremio) are derived per-session.
class IptvCatalogCache {
  IptvCatalogCache._();
  static final IptvCatalogCache instance = IptvCatalogCache._();

  static const _schemaVersion = 1;
  static const _xtreamContentTypes = ['live', 'vod', 'series'];

  Directory? _dir;
  int _writeSeq = 0;

  static String _keyForXtream(
    String serverUrl,
    String username,
    String contentType,
  ) =>
      'xc|$serverUrl|$username|$contentType';

  static String _keyForUrl(String url) => 'm3u|$url';

  /// The cache key for this playlist + content type, or null when the source
  /// isn't disk-cacheable.
  static String? keyForPlaylist(IptvPlaylist playlist, String contentType) {
    if (playlist.isFavorites ||
        playlist.isContinueWatching ||
        playlist.isStremioAddon ||
        playlist.isLocalFile) {
      return null;
    }
    if (playlist.isXtreamCodes) {
      return _keyForXtream(
        playlist.serverUrl!,
        playlist.username ?? '',
        contentType,
      );
    }
    if (playlist.url.isEmpty) return null;
    return _keyForUrl(playlist.url);
  }

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/iptv_catalog');
    await dir.create(recursive: true);
    _dir = dir;
    unawaited(_sweepStaleTmp(dir));
    return dir;
  }

  /// Crash leftovers: a kill between writeAsString and rename strands the
  /// temp file forever (nothing else lists this directory). Age-gated so an
  /// in-flight write's temp file is never touched.
  Future<void> _sweepStaleTmp(Directory dir) async {
    try {
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.contains('.json.tmp')) continue;
        final stat = await entry.stat();
        if (DateTime.now().difference(stat.modified) >
            const Duration(hours: 1)) {
          await entry.delete();
        }
      }
    } catch (e) {
      debugPrint('IptvCatalogCache: tmp sweep failed: $e');
    }
  }

  File _fileFor(Directory dir, String key) =>
      File('${dir.path}/${_hashKey(key)}.json');

  /// Read the snapshot for [key], or null when absent/stale-schema/corrupt.
  /// Decode runs off the UI isolate — VOD catalogs can be tens of MB.
  Future<IptvCatalogSnapshot?> read(String key) async {
    try {
      final file = _fileFor(await _cacheDir(), key);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final snapshot = await compute(_decodeSnapshot, raw);
      if (snapshot == null) {
        // Corrupt or old-schema file: drop it so it isn't re-parsed forever.
        unawaited(file.delete().then((_) {}, onError: (_) {}));
      }
      return snapshot;
    } catch (e) {
      debugPrint('IptvCatalogCache: read failed for $key: $e');
      return null;
    }
  }

  /// Persist a catalog snapshot. Atomic (temp file + rename) so a crash
  /// mid-write can never corrupt the previous good snapshot. Encode runs off
  /// the UI isolate. Failures are logged and swallowed — the cache is an
  /// optimization, never a load-blocker.
  Future<void> write(
    String key, {
    required List<IptvChannel> channels,
    required List<String> categories,
    String? epgUrl,
  }) async {
    if (channels.isEmpty) return; // never cache an empty catalog
    try {
      final dir = await _cacheDir();
      final payload = await compute(
        _encodeSnapshot,
        _EncodeJob(
          channels: channels,
          categories: categories,
          epgUrl: epgUrl,
          fetchedAtIso: DateTime.now().toIso8601String(),
        ),
      );
      final target = _fileFor(dir, key);
      final tmp = File('${target.path}.tmp${_writeSeq++}');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(target.path);
    } catch (e) {
      debugPrint('IptvCatalogCache: write failed for $key: $e');
    }
  }

  /// Drop all snapshots for an Xtream login (its credentials changed or the
  /// playlist was removed).
  Future<void> removeXtream(String serverUrl, String username) async {
    for (final type in _xtreamContentTypes) {
      await _remove(_keyForXtream(serverUrl, username, type));
    }
  }

  /// Drop the snapshot for an M3U URL playlist.
  Future<void> removeUrl(String url) => _remove(_keyForUrl(url));

  Future<void> _remove(String key) async {
    try {
      final file = _fileFor(await _cacheDir(), key);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('IptvCatalogCache: remove failed for $key: $e');
    }
  }

  /// Deterministic filename hash: two independent 32-bit FNV-1a passes
  /// (forward + reversed input) concatenated. Stable across runs/platforms —
  /// String.hashCode is not guaranteed to be.
  static String _hashKey(String key) {
    int fnv(Iterable<int> units) {
      var h = 0x811c9dc5;
      for (final u in units) {
        h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
      }
      return h;
    }

    final units = key.codeUnits;
    final h1 = fnv(units);
    final h2 = fnv(units.reversed);
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }
}

class _EncodeJob {
  final List<IptvChannel> channels;
  final List<String> categories;
  final String? epgUrl;
  final String fetchedAtIso;

  const _EncodeJob({
    required this.channels,
    required this.categories,
    required this.epgUrl,
    required this.fetchedAtIso,
  });
}

/// Isolate entry: compact snapshot JSON. Short keys on purpose — a 30k-item
/// VOD catalog is written on most refreshes and read on every cold start.
String _encodeSnapshot(_EncodeJob job) {
  return jsonEncode({
    'v': IptvCatalogCache._schemaVersion,
    'fetchedAt': job.fetchedAtIso,
    if (job.epgUrl != null) 'epgUrl': job.epgUrl,
    'categories': job.categories,
    'channels': [
      for (final c in job.channels)
        {
          'n': c.name,
          'u': c.url,
          if (c.logoUrl != null) 'l': c.logoUrl,
          if (c.group != null) 'g': c.group,
          if (c.duration != null) 'd': c.duration,
          if (c.contentType != null) 't': c.contentType,
          if (c.attributes.isNotEmpty) 'a': c.attributes,
          if (c.httpHeaders.isNotEmpty) 'h': c.httpHeaders,
        },
    ],
  });
}

/// Isolate entry: parse a snapshot file. Returns null on any structural
/// mismatch (corrupt file, older schema) — the caller deletes and refetches.
IptvCatalogSnapshot? _decodeSnapshot(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['v'] != IptvCatalogCache._schemaVersion) return null;
    final channelsJson = decoded['channels'];
    if (channelsJson is! List) return null;

    Map<String, String> stringMap(dynamic value) => value is Map
        ? {
            for (final e in value.entries)
              e.key.toString(): e.value.toString(),
          }
        : const {};

    final channels = <IptvChannel>[];
    for (final entry in channelsJson) {
      if (entry is! Map) continue;
      final name = entry['n']?.toString() ?? '';
      final url = entry['u']?.toString() ?? '';
      // Name may legitimately be empty (an M3U edge the parser admits) —
      // only a missing URL makes an entry unusable. Dropping what the
      // encoder wrote would make every snapshot differ from its fresh fetch
      // and flag a spurious "List updated" on every single visit.
      if (url.isEmpty) continue;
      channels.add(
        IptvChannel(
          name: name,
          url: url,
          logoUrl: entry['l']?.toString(),
          group: entry['g']?.toString(),
          duration: entry['d'] is int ? entry['d'] as int : null,
          contentType: entry['t']?.toString(),
          attributes: stringMap(entry['a']),
          httpHeaders: stringMap(entry['h']),
        ),
      );
    }
    if (channels.isEmpty) return null;

    return IptvCatalogSnapshot(
      channels: channels,
      categories: [
        for (final c in (decoded['categories'] as List? ?? const []))
          c.toString(),
      ],
      epgUrl: decoded['epgUrl']?.toString(),
      fetchedAt:
          DateTime.tryParse(decoded['fetchedAt']?.toString() ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0),
    );
  } catch (_) {
    return null;
  }
}
