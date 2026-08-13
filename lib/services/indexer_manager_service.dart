import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/indexer_manager_config.dart';
import '../models/profiles/connection_resource.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import 'profiles/profile_collection_resource_facade.dart';
import 'storage_service.dart';

class IndexerManagerTestResult {
  final bool success;
  final String message;

  const IndexerManagerTestResult({
    required this.success,
    required this.message,
  });
}

class _ProwlarrIndexerCacheEntry {
  final DateTime fetchedAt;
  final List<dynamic> indexers;

  const _ProwlarrIndexerCacheEntry({
    required this.fetchedAt,
    required this.indexers,
  });
}

class IndexerManagerService {
  static const Duration _prowlarrIndexerCacheTtl = Duration(minutes: 5);
  static final Map<String, _ProwlarrIndexerCacheEntry> _prowlarrIndexerCache =
      {};

  static Future<List<IndexerManagerConfig>> getConfigs() {
    return StorageService.getIndexerManagerConfigs(forSettings: false);
  }

  static Future<List<IndexerManagerConfig>> getEnabledConfigs() async {
    final configs = await getConfigs();
    return configs
        .where(
          (config) =>
              config.enabled &&
              config.normalizedBaseUrl.isNotEmpty &&
              config.apiKey.trim().isNotEmpty,
        )
        .toList();
  }

  static Future<IndexerManagerConfig?> getConfigForEngine(
    String engineId,
  ) async {
    if (!IndexerManagerConfig.isIndexerManagerEngine(engineId)) return null;
    final configs = await getConfigs();
    for (final config in configs) {
      if (config.engineId == engineId) return config;
    }
    return null;
  }

  static Future<List<Torrent>> searchKeyword(
    IndexerManagerConfig config,
    String query, {
    int? maxResults,
  }) async {
    if (query.trim().isEmpty) return [];
    await _authorize(config);

    final List<Torrent> result;
    switch (config.type) {
      case IndexerManagerType.jackett:
        result = await _searchJackett(config, {
          't': 'search',
          'q': query.trim(),
        }, maxResults: maxResults);
      case IndexerManagerType.prowlarr:
        result = await _searchProwlarr(
          config,
          query: query.trim(),
          maxResults: maxResults,
        );
    }
    await _authorize(config);
    return result;
  }

  static Future<List<Torrent>> searchByImdb(
    IndexerManagerConfig config,
    String imdbId, {
    required bool isMovie,
    int? season,
    int? episode,
    int? maxResults,
  }) async {
    final normalizedImdb = _normalizeImdbId(imdbId);
    if (normalizedImdb.isEmpty) return [];
    await _authorize(config);

    final List<Torrent> result;
    switch (config.type) {
      case IndexerManagerType.jackett:
        result = await _searchJackett(config, {
          't': isMovie ? 'movie' : 'tvsearch',
          'imdbid': normalizedImdb.replaceFirst('tt', ''),
          if (!isMovie && season != null) 'season': '$season',
          if (!isMovie && episode != null) 'ep': '$episode',
        }, maxResults: maxResults);
      case IndexerManagerType.prowlarr:
        result = await _searchProwlarr(
          config,
          imdbId: normalizedImdb,
          isMovie: isMovie,
          season: season,
          episode: episode,
          maxResults: maxResults,
        );
    }
    await _authorize(config);
    return result;
  }

  static Future<IndexerManagerTestResult> testConnection(
    IndexerManagerConfig config,
  ) async {
    try {
      await _authorize(config, allowUnbound: true);
      switch (config.type) {
        case IndexerManagerType.jackett:
          final uri = _jackettUri(config, {'t': 'caps'});
          final response = await http
              .get(uri)
              .timeout(Duration(seconds: config.timeoutSeconds));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return const IndexerManagerTestResult(
              success: true,
              message: 'Jackett responded successfully.',
            );
          }
          return IndexerManagerTestResult(
            success: false,
            message: 'Jackett returned HTTP ${response.statusCode}.',
          );
        case IndexerManagerType.prowlarr:
          final indexers = await _fetchProwlarrIndexers(
            config,
            allowCache: false,
          );
          return IndexerManagerTestResult(
            success: true,
            message: indexers.isNotEmpty
                ? 'Prowlarr connected with ${indexers.length} indexer(s).'
                : 'Prowlarr connected.',
          );
      }
    } catch (_) {
      return const IndexerManagerTestResult(
        success: false,
        message: 'Could not connect to this indexer manager.',
      );
    }
  }

  static Future<void> _authorize(
    IndexerManagerConfig config, {
    bool allowUnbound = false,
  }) => ProfileCollectionResourceFacade.authorizeExecution(
    resourceId: config.connectionResourceId,
    resourceRevision: config.connectionResourceRevision,
    acceptedTypes: const <ConnectionResourceType>{
      ConnectionResourceType.jackett,
      ConnectionResourceType.prowlarr,
    },
    feature: ProfileFeature.torrentSearch,
    allowUnbound: allowUnbound,
  );

  static Future<List<Torrent>> _searchJackett(
    IndexerManagerConfig config,
    Map<String, String> queryParams, {
    int? maxResults,
  }) async {
    final uri = _jackettUri(config, queryParams);
    debugPrint('IndexerManagerService: Jackett search started');

    final response = await http
        .get(uri)
        .timeout(Duration(seconds: config.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Jackett returned HTTP ${response.statusCode}');
    }

    final document = XmlDocument.parse(response.body);
    final items = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'item')
        .toList();

    final limit = maxResults ?? config.maxResults;
    return items
        .map((item) => _torrentFromTorznabItem(item, config))
        .whereType<Torrent>()
        .take(limit)
        .toList();
  }

  static Future<List<Torrent>> _searchProwlarr(
    IndexerManagerConfig config, {
    String? query,
    String? imdbId,
    bool isMovie = true,
    int? season,
    int? episode,
    int? maxResults,
  }) async {
    // Prowlarr's aggregate UI search endpoint (/api/v1/search) silently drops
    // the imdbId param and falls back to each indexer's "recently added"
    // feed instead of erroring, so imdb-based lookups go through the
    // per-indexer Torznab endpoint instead, which honors it correctly.
    if (imdbId != null && imdbId.isNotEmpty) {
      return _searchProwlarrByImdb(
        config,
        imdbId: imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        maxResults: maxResults,
      );
    }

    final params = <String, String>{
      if (query != null && query.isNotEmpty) 'query': query,
      if (query != null && query.isNotEmpty) 'type': 'search',
      if (config.categories.isNotEmpty)
        'categories': config.categories.join(','),
    };

    final uri = _appendPath(
      config.normalizedBaseUrl,
      '/api/v1/search',
    ).replace(queryParameters: params);
    debugPrint('IndexerManagerService: Prowlarr search started');

    final response = await http
        .get(uri, headers: _prowlarrHeaders(config))
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Prowlarr returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic> && decoded['data'] is List
        ? decoded['data'] as List<dynamic>
        : const [];

    final limit = maxResults ?? config.maxResults;
    return items
        .whereType<Map>()
        .map(
          (item) =>
              _torrentFromProwlarrItem(Map<String, dynamic>.from(item), config),
        )
        .whereType<Torrent>()
        .take(limit)
        .toList();
  }

  static Future<List<Torrent>> _searchProwlarrByImdb(
    IndexerManagerConfig config, {
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    int? maxResults,
  }) async {
    final indexerIds = await _prowlarrImdbCapableIndexerIds(
      config,
      isMovie: isMovie,
    );
    if (indexerIds.isEmpty) return [];

    final queryParams = <String, String>{
      't': isMovie ? 'movie' : 'tvsearch',
      'imdbid': imdbId.replaceFirst('tt', ''),
      if (!isMovie && season != null) 'season': '$season',
      if (!isMovie && episode != null) 'ep': '$episode',
    };

    // Each indexer is queried independently: one indexer failing (bad
    // upstream, timeout) shouldn't sink results from the others. But if
    // every one of them fails, that's a real error (e.g. Prowlarr
    // unreachable or a bad API key) and should surface as one instead of
    // silently looking like "no results".
    var anySucceeded = false;
    Object? lastError;
    final results = await Future.wait(
      indexerIds.map((id) async {
        try {
          final torrents = await _searchProwlarrTorznab(
            config,
            id,
            queryParams,
          );
          anySucceeded = true;
          return torrents;
        } catch (e) {
          lastError = e;
          debugPrint(
            'IndexerManagerService: Prowlarr Torznab search failed '
            '(${e.runtimeType})',
          );
          return const <Torrent>[];
        }
      }),
    );

    if (!anySucceeded && lastError != null) {
      throw Exception('Prowlarr Torznab search failed: $lastError');
    }

    final limit = maxResults ?? config.maxResults;
    return results.expand((list) => list).take(limit).toList();
  }

  /// Returns the ids of enabled, torrent-protocol Prowlarr indexers eligible
  /// for an imdbId-based search in the given movie/tv mode. An indexer whose
  /// capabilities Prowlarr hasn't probed yet (missing/empty searchParams) is
  /// included opportunistically: Prowlarr's own Torznab endpoint safely
  /// returns zero results for a mode an indexer doesn't actually support, so
  /// this can't leak wrong results, only costs an extra parallel request. An
  /// indexer that explicitly declares support without imdbId is excluded.
  static Future<List<int>> _prowlarrImdbCapableIndexerIds(
    IndexerManagerConfig config, {
    required bool isMovie,
  }) async {
    final indexers = await _fetchProwlarrIndexers(config);

    final paramsKey = isMovie ? 'movieSearchParams' : 'tvSearchParams';
    final ids = <int>[];
    for (final entry in indexers) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      if (map['enable'] != true) continue;
      // Torznab items carry no protocol marker, so a Usenet indexer here
      // would be parsed as a bogus "torrent" release. Only indexers that
      // explicitly declare the torrent protocol are eligible.
      if (map['protocol']?.toString().toLowerCase() != 'torrent') continue;
      final id = map['id'];
      if (id is! int) continue;

      final capabilities = map['capabilities'];
      final searchParams = capabilities is Map ? capabilities[paramsKey] : null;
      final knownUnsupported =
          searchParams is List &&
          !searchParams.any(
            (param) => param.toString().toLowerCase() == 'imdbid',
          );
      if (!knownUnsupported) ids.add(id);
    }
    return ids;
  }

  /// Fetches Prowlarr's indexer list (id, enable, protocol, and declared
  /// search capabilities per indexer), cached briefly since callers may
  /// retry the same search and this rarely changes between calls.
  static Future<List<dynamic>> _fetchProwlarrIndexers(
    IndexerManagerConfig config, {
    bool allowCache = true,
  }) async {
    final cacheKey = '${config.normalizedBaseUrl}|${config.apiKey}';
    if (allowCache) {
      final cached = _prowlarrIndexerCache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.fetchedAt) <
              _prowlarrIndexerCacheTtl) {
        return cached.indexers;
      }
    }

    final uri = _appendPath(config.normalizedBaseUrl, '/api/v1/indexer');
    final response = await http
        .get(uri, headers: _prowlarrHeaders(config))
        .timeout(Duration(seconds: config.timeoutSeconds));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Prowlarr returned HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final indexers = decoded is List ? decoded : const <dynamic>[];
    _prowlarrIndexerCache[cacheKey] = _ProwlarrIndexerCacheEntry(
      fetchedAt: DateTime.now(),
      indexers: indexers,
    );
    return indexers;
  }

  static Future<List<Torrent>> _searchProwlarrTorznab(
    IndexerManagerConfig config,
    int indexerId,
    Map<String, String> queryParams,
  ) async {
    final params = <String, String>{
      'apikey': config.apiKey.trim(),
      ...queryParams,
      if (config.categories.isNotEmpty) 'cat': config.categories.join(','),
    };
    final uri = _appendPath(
      config.normalizedBaseUrl,
      '/$indexerId/api',
    ).replace(queryParameters: params);
    debugPrint('IndexerManagerService: Prowlarr Torznab search started');

    final response = await http
        .get(uri)
        .timeout(Duration(seconds: config.timeoutSeconds));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Prowlarr indexer $indexerId returned HTTP ${response.statusCode}',
      );
    }

    final document = XmlDocument.parse(response.body);
    final items = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'item')
        .toList();

    return items
        .map((item) => _torrentFromTorznabItem(item, config))
        .whereType<Torrent>()
        .toList();
  }

  static Uri _jackettUri(
    IndexerManagerConfig config,
    Map<String, String> queryParams,
  ) {
    final indexerId = config.jackettIndexerId.trim().isEmpty
        ? 'all'
        : config.jackettIndexerId.trim();
    final path = '/api/v2.0/indexers/$indexerId/results/torznab/api';
    final params = <String, String>{
      'apikey': config.apiKey.trim(),
      ...queryParams,
      if (config.categories.isNotEmpty) 'cat': config.categories.join(','),
    };
    return _appendPath(
      config.normalizedBaseUrl,
      path,
    ).replace(queryParameters: params);
  }

  static Uri _appendPath(String baseUrl, String path) {
    final base = Uri.parse(baseUrl);
    final basePath = base.path.replaceFirst(RegExp(r'/+$'), '');
    final extraPath = path.replaceFirst(RegExp(r'^/+'), '');
    return base.replace(path: '$basePath/$extraPath');
  }

  static Map<String, String> _prowlarrHeaders(IndexerManagerConfig config) {
    return {'X-Api-Key': config.apiKey.trim(), 'Accept': 'application/json'};
  }

  static Torrent? _torrentFromTorznabItem(
    XmlElement item,
    IndexerManagerConfig config,
  ) {
    final title = _childText(item, 'title');
    final link = _childText(item, 'link');
    final guid = _childText(item, 'guid');
    final enclosureUrl = item
        .findElements('enclosure')
        .map((element) => element.getAttribute('url'))
        .whereType<String>()
        .firstOrNull;
    final attrs = _torznabAttrs(item);

    final magnetUrl = _firstMagnet([
      attrs['magneturl'],
      attrs['magnetUrl'],
      link,
      guid,
      enclosureUrl,
    ]);
    final torrentUrl = _firstHttpUrl([enclosureUrl, link]);
    final extractedHash = _extractInfoHash([
      attrs['infohash'],
      attrs['hash'],
      magnetUrl,
      guid,
    ]);

    if (extractedHash.isEmpty && magnetUrl == null && torrentUrl == null) {
      return null;
    }
    final infoHash = extractedHash.isNotEmpty
        ? extractedHash
        : _syntheticInfoHash(magnetUrl ?? torrentUrl ?? title ?? guid ?? '');
    final hasRealInfoHash = extractedHash.isNotEmpty;

    final size =
        int.tryParse(attrs['size'] ?? '') ??
        int.tryParse(_childText(item, 'size') ?? '') ??
        int.tryParse(
          item.findElements('enclosure').firstOrNull?.getAttribute('length') ??
              '',
        ) ??
        0;
    final seeders = int.tryParse(attrs['seeders'] ?? '') ?? 0;
    final peers = int.tryParse(attrs['peers'] ?? '') ?? 0;
    final leechers =
        int.tryParse(attrs['leechers'] ?? '') ??
        (peers > seeders ? peers - seeders : 0);
    final published = _parsePublished(_childText(item, 'pubDate'));

    return Torrent(
      rowid: _stableId(
        infoHash.isNotEmpty
            ? infoHash
            : (magnetUrl ?? torrentUrl ?? title ?? ''),
      ),
      infohash: infoHash,
      name: title ?? guid ?? 'Unknown release',
      sizeBytes: size,
      createdUnix: published,
      seeders: seeders,
      leechers: leechers,
      completed: 0,
      scrapedDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      category: attrs['category'] ?? config.type.label,
      source: config.displayName,
      magnetUrl: magnetUrl,
      torrentUrl: torrentUrl,
      hasRealInfoHash: hasRealInfoHash,
    );
  }

  static Torrent? _torrentFromProwlarrItem(
    Map<String, dynamic> item,
    IndexerManagerConfig config,
  ) {
    final protocol = _firstString(item, const ['protocol'])?.toLowerCase();
    if (protocol != null && protocol.isNotEmpty && protocol != 'torrent') {
      return null;
    }

    final title = _firstString(item, const ['title', 'releaseTitle', 'name']);
    final magnetUrl = _firstMagnet([
      _firstString(item, const ['magnetUrl', 'magnet', 'magnetLink']),
      _firstString(item, const ['downloadUrl', 'guid']),
    ]);
    final torrentUrl = _firstHttpUrl([
      _firstString(item, const ['downloadUrl', 'download_url']),
    ]);
    final extractedHash = _extractInfoHash([
      _firstString(item, const ['infoHash', 'infohash', 'hash']),
      magnetUrl,
      _firstString(item, const ['guid']),
    ]);

    if (extractedHash.isEmpty && magnetUrl == null && torrentUrl == null) {
      return null;
    }
    final infoHash = extractedHash.isNotEmpty
        ? extractedHash
        : _syntheticInfoHash(magnetUrl ?? torrentUrl ?? title ?? '');
    final hasRealInfoHash = extractedHash.isNotEmpty;

    final size = _intValue(item, const ['size', 'sizeBytes']) ?? 0;
    final seeders = _intValue(item, const ['seeders', 'seedCount']) ?? 0;
    final leechers = _intValue(item, const ['leechers', 'leechCount']) ?? 0;
    final published = _parsePublished(
      _firstString(item, const ['publishDate', 'publish_date', 'date']),
    );
    final source =
        _firstString(item, const ['indexer', 'indexerName']) ??
        config.displayName;

    return Torrent(
      rowid: _stableId(
        infoHash.isNotEmpty
            ? infoHash
            : (magnetUrl ?? torrentUrl ?? title ?? ''),
      ),
      infohash: infoHash,
      name: title ?? 'Unknown release',
      sizeBytes: size,
      createdUnix: published,
      seeders: seeders,
      leechers: leechers,
      completed: 0,
      scrapedDate: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      category: source,
      source: config.displayName,
      magnetUrl: magnetUrl,
      torrentUrl: torrentUrl,
      hasRealInfoHash: hasRealInfoHash,
    );
  }

  static String? _childText(XmlElement item, String childName) {
    return item
        .findElements(childName)
        .map((element) => element.innerText.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
  }

  static Map<String, String> _torznabAttrs(XmlElement item) {
    final attrs = <String, String>{};
    for (final element in item.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'attr') continue;
      final name = element.getAttribute('name');
      final value = element.getAttribute('value');
      if (name != null && value != null) {
        attrs[name] = value;
      }
    }
    return attrs;
  }

  static String? _firstString(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  static int? _intValue(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static String? _firstMagnet(Iterable<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null && text.toLowerCase().startsWith('magnet:')) {
        return text;
      }
    }
    return null;
  }

  static String? _firstHttpUrl(Iterable<String?> values) {
    for (final value in values) {
      final text = value?.trim();
      if (text != null &&
          (text.toLowerCase().startsWith('http://') ||
              text.toLowerCase().startsWith('https://'))) {
        return text;
      }
    }
    return null;
  }

  static String _extractInfoHash(Iterable<String?> values) {
    final hashRegex = RegExp(r'([a-fA-F0-9]{40}|[a-zA-Z2-7]{32})');
    for (final value in values) {
      final text = value?.trim();
      if (text == null || text.isEmpty) continue;
      final lower = text.toLowerCase();
      if (lower.startsWith('magnet:')) {
        final uri = Uri.tryParse(text);
        final xt = uri?.queryParametersAll['xt']?.firstOrNull;
        final hash = xt?.split(':').last.trim();
        if (hash != null && hashRegex.hasMatch(hash)) {
          return hash.toLowerCase();
        }
      }
      final match = hashRegex.firstMatch(text);
      if (match != null) return match.group(1)!.toLowerCase();
    }
    return '';
  }

  static String _normalizeImdbId(String imdbId) {
    final trimmed = imdbId.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
  }

  static int _parsePublished(String? value) {
    if (value == null || value.trim().isEmpty) return 0;
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.millisecondsSinceEpoch ~/ 1000;
    try {
      return HttpDate.parse(value).millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return 0;
    }
  }

  static int _stableId(String value) {
    var hash = 0;
    for (final codeUnit in value.codeUnits) {
      hash = 0x1fffffff & (hash + codeUnit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash;
  }

  static String _syntheticInfoHash(String value) {
    return sha1.convert(utf8.encode(value)).toString();
  }
}
