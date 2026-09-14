import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/iptv_playlist.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../utils/m3u_parser.dart';
import 'iptv_catalog_key.dart';
import 'iptv_catalog_db.dart';
import 'iptv_load_phase.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'profiles/profile_runtime.dart';

/// Service for fetching and managing IPTV M3U playlists
class IptvService {
  static final IptvService _instance = IptvService._internal();
  static IptvService get instance => _instance;
  IptvService._internal();

  // Cache for parsed playlists (URL -> result)
  final Map<String, _CachedPlaylist> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  // Parsed playlists are large (a big M3U yields tens of thousands of channel
  // objects), so keep only a few resident — the TTL alone never frees memory
  // for distinct URLs.
  static const _maxCachedPlaylists = 3;

  // Refuse to buffer arbitrarily large playlists: a 100MB+ M3U held as bytes
  // + decoded string + parsed channels at once can OOM a low-RAM TV.
  static const _maxPlaylistBytes = 50 * 1024 * 1024; // 50 MB

  // Hard ceiling on the whole download so a slow-dripping server can't pin
  // the add/loading UI indefinitely (the per-chunk timeout below only catches
  // full stalls). More generous than the old flat 30s so big-but-healthy
  // playlists still succeed.
  static const _fetchDeadline = Duration(minutes: 2);

  /// Fetch and parse an M3U playlist from URL
  Future<IptvParseResult> fetchPlaylist(
    String url, {
    bool forceRefresh = false,
    String? numberingSourceKey,
    IptvLoadPhase? onPhase,
    String? connectionResourceId,
    int? connectionResourceRevision,
    bool allowUnbound = false,
    bool Function()? isCurrent,
  }) async {
    final startingScope = ProfileRuntime.scope.value;
    final ingestTarget = IptvCatalogDb.captureWriteTarget();
    void assertCurrent() {
      if (ProfileRuntime.scope.value != startingScope ||
          isCurrent?.call() == false) {
        throw StateError('IPTV request is no longer current');
      }
    }

    Future<void> authorize() async {
      assertCurrent();
      await ProfileCollectionResourceFacade.authorizeExecution(
        resourceId: connectionResourceId,
        resourceRevision: connectionResourceRevision,
        acceptedTypes: const <ConnectionResourceType>{
          ConnectionResourceType.iptvM3u,
        },
        feature: ProfileFeature.iptv,
        allowUnbound: allowUnbound,
      );
      assertCurrent();
    }

    await authorize();
    final result = await _fetchPlaylistAuthorized(
      url,
      forceRefresh: forceRefresh,
      numberingSourceKey: numberingSourceKey,
      onPhase: onPhase,
      ingestTarget: ingestTarget,
      beforeIngest: authorize,
    );
    await authorize();
    return result;
  }

  Future<IptvParseResult> _fetchPlaylistAuthorized(
    String url, {
    bool forceRefresh = false,
    String? numberingSourceKey,
    IptvLoadPhase? onPhase,
    required IptvCatalogWriteTarget? ingestTarget,
    required Future<void> Function() beforeIngest,
  }) async {
    // With the catalog database open, the parse worker ingests straight
    // into it and this service's in-memory cache is bypassed — freshness
    // policy moves to the caller (snapshot.ingestedAt).
    final ingestToDb = ingestTarget != null;

    // Check cache
    if (!ingestToDb && !forceRefresh && _cache.containsKey(url)) {
      final cached = _cache[url]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint('IptvService: Using cached playlist');
        return cached.result;
      }
    }

    debugPrint('IptvService: Fetching playlist');

    onPhase?.call(IptvLoadPhases.contacting);
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Debrify/1.0';
      request.headers['Accept'] = '*/*';
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamed.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch playlist: HTTP ${streamed.statusCode}',
        );
      }

      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > _maxPlaylistBytes) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error:
              'Playlist is too large (${declaredLength ~/ (1024 * 1024)} MB, '
              'limit ${_maxPlaylistBytes ~/ (1024 * 1024)} MB)',
        );
      }

      // Stream the body so an over-limit (or lying Content-Length) download
      // aborts early instead of buffering the whole payload.
      final startedAt = DateTime.now();
      final builder = BytesBuilder(copy: false);
      onPhase?.call(
        IptvLoadPhases.downloading,
        bytes: 0,
        totalBytes: declaredLength,
      );
      await for (final chunk in streamed.stream.timeout(
        const Duration(seconds: 60),
      )) {
        builder.add(chunk);
        // Fired per chunk; the page stores it and repaints on its own 1Hz
        // tick, so this never costs a frame.
        onPhase?.call(
          IptvLoadPhases.downloading,
          bytes: builder.length,
          totalBytes: declaredLength,
        );
        if (DateTime.now().difference(startedAt) > _fetchDeadline) {
          return IptvParseResult(
            channels: [],
            categories: [],
            error: 'Playlist download timed out',
          );
        }
        if (builder.length > _maxPlaylistBytes) {
          return IptvParseResult(
            channels: [],
            categories: [],
            error:
                'Playlist is too large (over '
                '${_maxPlaylistBytes ~/ (1024 * 1024)} MB)',
          );
        }
      }

      final bytes = builder.takeBytes();
      onPhase?.call(IptvLoadPhases.processing, bytes: bytes.length);

      await beforeIngest();
      final result = await _parseBytes(
        bytes,
        ingestCatalogKey: ingestToDb ? IptvCatalogKey.forUrl(url) : null,
        ingestTarget: ingestTarget,
        beforeIngest: beforeIngest,
        numberingSourceKey: numberingSourceKey,
      );

      // An ingested result IS the cache — the rows are on disk and nothing
      // big should linger on this heap.
      if (result.ingest == null) {
        _cache[url] = _CachedPlaylist(
          result: result,
          fetchedAt: DateTime.now(),
        );
        _evictCache();
      }

      debugPrint(
        'IptvService: Parsed '
        '${result.ingest?.channelCount ?? result.channels.length} channels, '
        '${result.categories.length} categories'
        '${result.ingest != null ? ' (ingested to catalog DB)' : ''}',
      );

      return result;
    } catch (error) {
      debugPrint('IptvService: Error fetching playlist (${error.runtimeType})');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch playlist',
      );
    } finally {
      client.close();
    }
  }

  /// Drop expired entries, then the oldest beyond the cap.
  void _evictCache() {
    final now = DateTime.now();
    _cache.removeWhere((_, c) => now.difference(c.fetchedAt) >= _cacheDuration);
    while (_cache.length > _maxCachedPlaylists) {
      String? oldestKey;
      DateTime? oldestAt;
      _cache.forEach((key, cached) {
        if (oldestAt == null || cached.fetchedAt.isBefore(oldestAt!)) {
          oldestAt = cached.fetchedAt;
          oldestKey = key;
        }
      });
      _cache.remove(oldestKey);
    }
  }

  /// Filter channels by category
  List<IptvChannel> filterByCategory(
    List<IptvChannel> channels,
    String? category,
  ) {
    if (category == null || category.isEmpty) {
      return channels;
    }
    return channels.where((c) => c.group == category).toList();
  }

  /// Search channels by name or group (case-insensitive). Matches against the
  /// channel's precomputed [IptvChannel.searchKey] so a keystroke over a huge
  /// playlist is one contains() per channel, not fresh toLowerCase() copies of
  /// every name and group.
  List<IptvChannel> searchChannels(List<IptvChannel> channels, String query) {
    if (query.isEmpty) {
      return channels;
    }
    final lowerQuery = query.toLowerCase();
    return channels.where((c) => c.searchKey.contains(lowerQuery)).toList();
  }

  /// Clear cache for a specific URL or all
  void clearCache([String? url]) {
    if (url != null) {
      _cache.remove(url);
    } else {
      _cache.clear();
    }
  }

  /// Validate if a URL looks like a valid M3U URL
  static bool isValidPlaylistUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        return false;
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Parse M3U content directly (for file-based playlists)
  Future<IptvParseResult> parseContent(String content) async {
    debugPrint(
      'IptvService: Parsing content directly (${content.length} chars)',
    );
    final result = await _parse(content);
    debugPrint(
      'IptvService: Parsed ${result.channels.length} channels, ${result.categories.length} categories',
    );
    return result;
  }

  /// Parse a downloaded playlist body. Above the inline threshold the raw
  /// BYTES are handed to the worker as [TransferableTypedData] (moved, not
  /// copied — the Xtream path's proven pattern) and UTF-8 decoding happens
  /// THERE. Decoding on this isolate used to build a UTF-16 string up to 2×
  /// the payload (a multi-second synchronous stall on a 50 MB playlist —
  /// straight ANR territory) and `compute` then copied that whole string
  /// again into the worker: ~250 MB peak across both heaps for a payload
  /// the limit calls acceptable.
  Future<IptvParseResult> _parseBytes(
    Uint8List bytes, {
    String? ingestCatalogKey,
    IptvCatalogWriteTarget? ingestTarget,
    Future<void> Function()? beforeIngest,
    String? numberingSourceKey,
  }) async {
    if (bytes.length <= _inlineParseBytes) {
      return _parse(
        M3uParser.decodeBytes(bytes),
        ingestCatalogKey: ingestCatalogKey,
        ingestTarget: ingestTarget,
        beforeIngest: beforeIngest,
        numberingSourceKey: numberingSourceKey,
      );
    }
    if (ingestCatalogKey != null) {
      final job = _M3uIngestJob(
        bytes: TransferableTypedData.fromList([bytes]),
        dbPath: ingestTarget!.path,
        catalogKey: ingestCatalogKey,
        numberingSourceKey: numberingSourceKey,
      );
      // Only the parse+ingest hop runs behind the process-wide catalog gate
      // — never the download above it. Holding the gate across a network
      // fetch (up to the 2-minute deadline) used to block settings
      // deletions, EPG scans and migrations behind a slow server.
      // Re-entrant: a caller already inside the gate runs this inline.
      return IptvCatalogDb.runWithWriteTarget(ingestTarget, () async {
        await beforeIngest?.call();
        return compute(_parseAndIngestM3u, job);
      });
    }
    // No-DB path (catalog DB unavailable): decode + parse in the worker. The
    // parsed channels still copy back — unavoidable while this source stays
    // materialized — but the decoded-string copy no longer does.
    return compute(_decodeAndParseM3u, TransferableTypedData.fromList([bytes]));
  }

  /// Bodies at or under this size are parsed inline — isolate spin-up costs
  /// more than the parse itself down there.
  static const _inlineParseBytes = 100 * 1024;

  /// Parse already-decoded M3U text off the UI isolate when large. With
  /// [ingestCatalogKey] set, the worker also writes the catalog into the DB
  /// and returns a receipt instead of the channel list. String-based entry
  /// kept for the local-file path ([parseContent]), whose content is already
  /// a String in storage.
  Future<IptvParseResult> _parse(
    String content, {
    String? ingestCatalogKey,
    IptvCatalogWriteTarget? ingestTarget,
    Future<void> Function()? beforeIngest,
    String? numberingSourceKey,
  }) async {
    if (ingestCatalogKey != null) {
      final job = _M3uIngestJob(
        content: content,
        dbPath: ingestTarget!.path,
        catalogKey: ingestCatalogKey,
        numberingSourceKey: numberingSourceKey,
      );
      // Gated for the same reason as the bytes path above.
      return IptvCatalogDb.runWithWriteTarget(ingestTarget, () async {
        await beforeIngest?.call();
        return content.length > _inlineParseBytes
            ? await compute(_parseAndIngestM3u, job)
            : _parseAndIngestM3u(job);
      });
    }
    return content.length > _inlineParseBytes
        ? await compute(M3uParser.parse, content)
        : M3uParser.parse(content);
  }
}

class _M3uIngestJob {
  /// Exactly one of [bytes] / [content] is set. Bytes travel zero-copy
  /// (transferable); a String would be deep-copied into the worker.
  final TransferableTypedData? bytes;
  final String? content;
  final String dbPath;
  final String catalogKey;
  final String? numberingSourceKey;

  const _M3uIngestJob({
    this.bytes,
    this.content,
    required this.dbPath,
    required this.catalogKey,
    required this.numberingSourceKey,
  });
}

/// Worker entry: decode (when bytes were transferred), parse AND ingest in
/// one hop, so neither the decoded text nor the channel objects ever cross
/// back to the UI isolate. An empty or failed parse is returned as-is and
/// deliberately NOT ingested — a transient bad fetch must not wipe a
/// previously good stored catalog.
IptvParseResult _parseAndIngestM3u(_M3uIngestJob job) {
  final content =
      job.content ??
      M3uParser.decodeBytes(job.bytes!.materialize().asUint8List());
  final result = M3uParser.parse(content);
  if (result.hasError || result.channels.isEmpty) return result;
  final digest = IptvCatalogDb.ingest(
    dbPath: job.dbPath,
    catalogKey: job.catalogKey,
    channels: result.channels,
    categories: result.categories,
    epgUrl: result.epgUrl,
    numberingSourceKey: job.numberingSourceKey,
  );
  return IptvParseResult(
    channels: const [],
    categories: result.categories,
    warning: result.warning,
    epgUrl: result.epgUrl,
    ingest: CatalogIngestReceipt(
      catalogKey: job.catalogKey,
      channelCount: result.channels.length,
      contentDigest: digest,
    ),
  );
}

/// Worker entry for the no-DB path: decode transferred bytes and parse.
IptvParseResult _decodeAndParseM3u(TransferableTypedData bytes) =>
    M3uParser.parse(M3uParser.decodeBytes(bytes.materialize().asUint8List()));

class _CachedPlaylist {
  final IptvParseResult result;
  final DateTime fetchedAt;

  _CachedPlaylist({required this.result, required this.fetchedAt});
}
