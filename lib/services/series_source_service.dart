import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profiles/profile_preferences.dart';
import 'webdav_sync/webdav_sync_hot_merge.dart';
import 'webdav_sync/webdav_sync_tombstones.dart';

/// Represents a bound torrent source for a series.
/// When set, episode playback skips torrent search and uses this source directly.
class SeriesSource {
  static const String localService = 'local';
  static const String addonDirectService = 'stremio_direct';
  static const String localKindMovieFile = 'movie_file';
  static const String localKindSeriesFolder = 'series_folder';
  static const String cloudKindFile = 'file';
  static const String cloudKindFolder = 'folder';
  static const String cloudKindWebDownload = 'web_download';

  final String torrentHash;
  final String torrentName;
  final String debridService;
  final String debridTorrentId;
  // Provider-native cloud bindings do not expose an infohash. Their stable
  // file/folder/web-download reference lives in [debridTorrentId], while this
  // discriminator tells playback how to resolve it without fabricating a
  // magnet. Hash-backed records leave this null.
  final String? cloudSourceKind;
  final int boundAt; // epoch millis
  final String? localPath;
  final String? localUri;
  final String? localKind;
  final int? localSizeBytes;
  final int? localModifiedAt;
  final String? addonId;
  final String? addonKey;
  final String? streamKey;
  final int? streamIndex;

  const SeriesSource({
    required this.torrentHash,
    required this.torrentName,
    required this.debridService,
    required this.debridTorrentId,
    this.cloudSourceKind,
    required this.boundAt,
    this.localPath,
    this.localUri,
    this.localKind,
    this.localSizeBytes,
    this.localModifiedAt,
    this.addonId,
    this.addonKey,
    this.streamKey,
    this.streamIndex,
  });

  bool get isLocal => debridService == localService;
  bool get isProviderNativeCloud =>
      !isLocal &&
      torrentHash.isEmpty &&
      debridTorrentId.trim().isNotEmpty &&
      (cloudSourceKind == cloudKindFile ||
          cloudSourceKind == cloudKindFolder ||
          cloudSourceKind == cloudKindWebDownload);
  bool get isAddonDirect =>
      debridService == addonDirectService &&
      (addonId?.trim().isNotEmpty ?? false) &&
      (addonKey?.trim().isNotEmpty ?? false);

  /// Stable identity used for dedupe, reorder keys, and removal. Existing
  /// hash-backed bindings retain their exact behavior; only hashless cloud
  /// bindings fall back to provider + kind + provider id.
  String get bindingKey {
    if (torrentHash.isNotEmpty) return 'hash:$torrentHash';
    if (isLocal) {
      final path = (localPath ?? debridTorrentId).trim();
      return 'local:$path';
    }
    if (isAddonDirect) {
      // [streamIndex] is deliberately NOT part of the identity. It is the
      // stream's position in the addon's response, which moves between searches
      // as cache state and seeders change — so including it made a replay of the
      // SAME file compute a new key, miss the dedupe in _autoBindSeriesOnPlay /
      // _rebindOnSourceSwitch, and append a duplicate pin on every play. It is
      // still stored, because re-resolution needs it; it just cannot be identity.
      // [streamKey] is the real identity: a URL-free stream profile (see
      // StremioStream.streamKey), so it survives signed/expiring links.
      return 'direct:${addonKey!.trim()}:${streamKey?.trim() ?? ''}';
    }
    return 'cloud:$debridService:${cloudSourceKind ?? ''}:${debridTorrentId.trim()}';
  }

  /// Kept in lock-step with [bindingKey] — it too ignores the response
  /// position, or the two could disagree about whether a stream is already
  /// pinned. Takes no stream index for that reason.
  bool matchesAddonDirect({
    required String? candidateAddonKey,
    required String? candidateStreamKey,
  }) =>
      isAddonDirect &&
      addonKey == candidateAddonKey &&
      streamKey == candidateStreamKey;

  bool get isLocalMovieFile =>
      isLocal && (localKind == null || localKind == localKindMovieFile);
  bool get isLocalSeriesFolder => isLocal && localKind == localKindSeriesFolder;

  static String localSourceHash(String path) {
    final normalizedPath = path.trim();
    final digest = sha1.convert(utf8.encode(normalizedPath)).toString();
    return 'local:$digest';
  }

  /// Secret-free stable reference for provider-native items whose provider
  /// exposes only an original URL (for example AllDebrid saved links).
  static String opaqueCloudReference(String value) =>
      sha256.convert(utf8.encode(value.trim())).toString();

  Map<String, dynamic> toJson() => {
    'torrentHash': torrentHash,
    'torrentName': torrentName,
    'debridService': debridService,
    'debridTorrentId': debridTorrentId,
    if (cloudSourceKind != null) 'cloudSourceKind': cloudSourceKind,
    'boundAt': boundAt,
    if (localPath != null) 'localPath': localPath,
    if (localUri != null) 'localUri': localUri,
    if (localKind != null) 'localKind': localKind,
    if (localSizeBytes != null) 'localSizeBytes': localSizeBytes,
    if (localModifiedAt != null) 'localModifiedAt': localModifiedAt,
    if (addonId != null) 'addonId': addonId,
    if (addonKey != null) 'addonKey': addonKey,
    if (streamKey != null) 'streamKey': streamKey,
    if (streamIndex != null) 'streamIndex': streamIndex,
  };

  factory SeriesSource.fromJson(Map<String, dynamic> json) => SeriesSource(
    torrentHash: json['torrentHash'] as String? ?? '',
    torrentName: json['torrentName'] as String? ?? '',
    debridService: json['debridService'] as String? ?? 'rd',
    debridTorrentId: json['debridTorrentId'] as String? ?? '',
    cloudSourceKind: json['cloudSourceKind'] as String?,
    boundAt: json['boundAt'] as int? ?? 0,
    localPath: json['localPath'] as String?,
    localUri: json['localUri'] as String?,
    localKind: json['localKind'] as String?,
    localSizeBytes: json['localSizeBytes'] as int?,
    localModifiedAt: json['localModifiedAt'] as int?,
    addonId: json['addonId'] as String?,
    addonKey: json['addonKey'] as String?,
    streamKey: json['streamKey'] as String?,
    streamIndex: json['streamIndex'] as int?,
  );
}

/// Manages series-to-torrent source bindings (multiple sources per series).
/// Stores in SharedPreferences with key prefix 'series_source_'.
/// Backward compatible: reads old single-source format and migrates to list.
class SeriesSourceService {
  static const String _prefix = 'series_source_';

  /// Get all bound sources for a series, ordered by priority (first = highest).
  static Future<List<SeriesSource>> getSources(String imdbId) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString('$_prefix$imdbId');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      // New format: JSON array
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((j) => SeriesSource.fromJson(j))
            .toList();
      }
      // Old format: single JSON object — migrate
      if (decoded is Map<String, dynamic>) {
        final source = SeriesSource.fromJson(decoded);
        // Auto-migrate to list format
        await _saveSources(prefs, imdbId, [source]);
        return [source];
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Get the first (highest priority) source. Convenience for quick checks.
  static Future<SeriesSource?> getSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isEmpty ? null : sources.first;
  }

  /// Add a source to the list (appends at end = lowest priority).
  /// Hash-backed sources dedupe exactly as before. Provider-native cloud
  /// sources dedupe by provider + kind + stable provider id.
  static Future<void> addSource(String imdbId, SeriesSource source) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    // Replace if the same stable binding already exists.
    final existingIdx = sources.indexWhere(
      (s) => s.bindingKey == source.bindingKey,
    );
    if (existingIdx >= 0) {
      sources[existingIdx] = source;
    } else {
      sources.add(source);
    }
    await _saveSources(prefs, imdbId, sources);
  }

  /// Remove a specific source by torrentHash.
  static Future<void> removeSourceByHash(
    String imdbId,
    String torrentHash,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    final removed = sources
        .where((source) => source.torrentHash == torrentHash)
        .toList(growable: false);
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      removed
          .where((source) => !source.isLocal)
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    sources.removeWhere((source) => source.torrentHash == torrentHash);
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Remove one exact source, including a provider-native source with no hash.
  static Future<void> removeSourceEntry(
    String imdbId,
    SeriesSource source,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    final removed = sources.where(
      (candidate) => candidate.bindingKey == source.bindingKey,
    );
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      removed
          .where((source) => !source.isLocal)
          .map(
            (candidate) =>
                WebDavSyncRecordKey.source(imdbId, candidate.bindingKey),
          ),
    );
    sources.removeWhere((s) => s.bindingKey == source.bindingKey);
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Remove all sources for a series.
  static Future<void> removeAllSources(String imdbId) async {
    final prefs = await ProfilePreferences.instance();
    final sources = await getSources(imdbId);
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      sources
          .where((source) => !source.isLocal)
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    await prefs.remove('$_prefix$imdbId');
  }

  /// Replace the entire source list (for reordering).
  static Future<void> setSources(
    String imdbId,
    List<SeriesSource> sources,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final existing = await getSources(imdbId);
    final retained = sources.map((source) => source.bindingKey).toSet();
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
      existing
          .where(
            (source) =>
                !source.isLocal && !retained.contains(source.bindingKey),
          )
          .map(
            (source) => WebDavSyncRecordKey.source(imdbId, source.bindingKey),
          ),
    );
    if (sources.isEmpty) {
      await prefs.remove('$_prefix$imdbId');
    } else {
      await _saveSources(prefs, imdbId, sources);
    }
  }

  /// Check if any sources are bound.
  static Future<bool> hasSource(String imdbId) async {
    final sources = await getSources(imdbId);
    return sources.isNotEmpty;
  }

  // Keep old setSource/removeSource for backward compatibility during transition
  /// @deprecated Use addSource instead.
  static Future<void> setSource(String imdbId, SeriesSource source) =>
      addSource(imdbId, source);

  /// @deprecated Use removeAllSources instead.
  static Future<void> removeSource(String imdbId) => removeAllSources(imdbId);

  static Future<void> _saveSources(
    SharedPreferences prefs,
    String imdbId,
    List<SeriesSource> sources,
  ) async {
    final jsonList = sources.map((s) => s.toJson()).toList();
    await prefs.setString('$_prefix$imdbId', jsonEncode(jsonList));
  }
}
