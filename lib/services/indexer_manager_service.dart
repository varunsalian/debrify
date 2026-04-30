import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../models/indexer_manager_config.dart';
import '../models/torrent.dart';
import 'storage_service.dart';

class IndexerManagerTestResult {
  final bool success;
  final String message;

  const IndexerManagerTestResult({
    required this.success,
    required this.message,
  });
}

class IndexerManagerService {
  static Future<List<IndexerManagerConfig>> getConfigs() {
    return StorageService.getIndexerManagerConfigs();
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

    switch (config.type) {
      case IndexerManagerType.jackett:
        return _searchJackett(config, {
          't': 'search',
          'q': query.trim(),
        }, maxResults: maxResults);
      case IndexerManagerType.prowlarr:
        return _searchProwlarr(
          config,
          query: query.trim(),
          maxResults: maxResults,
        );
    }
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

    switch (config.type) {
      case IndexerManagerType.jackett:
        return _searchJackett(config, {
          't': isMovie ? 'movie' : 'tvsearch',
          'imdbid': normalizedImdb.replaceFirst('tt', ''),
          if (!isMovie && season != null) 'season': '$season',
          if (!isMovie && episode != null) 'ep': '$episode',
        }, maxResults: maxResults);
      case IndexerManagerType.prowlarr:
        return _searchProwlarr(
          config,
          imdbId: normalizedImdb,
          isMovie: isMovie,
          season: season,
          episode: episode,
          maxResults: maxResults,
        );
    }
  }

  static Future<IndexerManagerTestResult> testConnection(
    IndexerManagerConfig config,
  ) async {
    try {
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
          final uri = _appendPath(config.normalizedBaseUrl, '/api/v1/indexer');
          final response = await http
              .get(uri, headers: _prowlarrHeaders(config))
              .timeout(Duration(seconds: config.timeoutSeconds));
          if (response.statusCode >= 200 && response.statusCode < 300) {
            final decoded = jsonDecode(response.body);
            final count = decoded is List ? decoded.length : 0;
            return IndexerManagerTestResult(
              success: true,
              message: count > 0
                  ? 'Prowlarr connected with $count indexer(s).'
                  : 'Prowlarr connected.',
            );
          }
          return IndexerManagerTestResult(
            success: false,
            message: 'Prowlarr returned HTTP ${response.statusCode}.',
          );
      }
    } catch (e) {
      return IndexerManagerTestResult(success: false, message: e.toString());
    }
  }

  static Future<List<Torrent>> _searchJackett(
    IndexerManagerConfig config,
    Map<String, String> queryParams, {
    int? maxResults,
  }) async {
    final uri = _jackettUri(config, queryParams);
    debugPrint(
      'IndexerManagerService: Jackett search ${uri.replace(queryParameters: {...uri.queryParameters, 'apikey': '***'})}',
    );

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
    final params = <String, String>{
      if (query != null && query.isNotEmpty) 'query': query,
      if (query != null && query.isNotEmpty) 'type': 'search',
      if (imdbId != null && imdbId.isNotEmpty) 'imdbId': imdbId,
      if (imdbId != null && imdbId.isNotEmpty)
        'type': isMovie ? 'movie' : 'tvsearch',
      if (!isMovie && season != null) 'season': '$season',
      if (!isMovie && episode != null) 'episode': '$episode',
      if (config.categories.isNotEmpty)
        'categories': config.categories.join(','),
    };

    final uri = _appendPath(
      config.normalizedBaseUrl,
      '/api/v1/search',
    ).replace(queryParameters: params);
    debugPrint('IndexerManagerService: Prowlarr search $uri');

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
