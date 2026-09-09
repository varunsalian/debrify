import 'dart:convert';
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/home_collection.dart';
import '../models/stremio_addon.dart';
import 'collection_catalog_pager.dart';
import 'tmdb_http_client.dart';
import 'trakt/trakt_constants.dart';
import 'trakt/trakt_item_transformer.dart';

/// Public collection catalogs. Credentials are sent only to fixed API hosts;
/// imported JSON controls IDs and supported query fields, never request URLs.
class CollectionNativeSourceService {
  CollectionNativeSourceService({
    http.Client? client,
    http.Client Function()? tmdbClientFactory,
    String? tmdbToken,
    this.resolveIds = true,
    this.enrichmentBudget = const Duration(seconds: 3),
    this.requestBudget = const Duration(seconds: 25),
    this.retryDelay = const Duration(milliseconds: 200),
  }) : _client = client ?? http.Client(),
       _tmdbClientFactory =
           tmdbClientFactory ??
           (client != null
               ? (() => client)
               : (() => TmdbHttpClient(dnsCache: _dnsCache))),
       _ownsTmdbClients = tmdbClientFactory != null || client == null,
       _tmdbToken =
           tmdbToken ?? const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');

  static final instance = CollectionNativeSourceService();
  final http.Client _client;
  static final _dnsCache = TmdbDnsCache();
  final http.Client Function() _tmdbClientFactory;
  final bool _ownsTmdbClients;
  final _activeClients = <http.Client>{};
  final _idleClients = <http.Client>[];
  bool _closed = false;
  final Duration requestBudget;
  final Duration retryDelay;
  DateTime? _rateLimitedUntil;
  final identityChanges = ValueNotifier<int>(0);
  final _responses = <String, ({DateTime expires, String body})>{};
  final _pendingResponses = <String, Future<Map<String, dynamic>>>{};
  int _responseBytes = 0;
  final String _tmdbToken;
  void close() {
    if (_closed) return;
    _closed = true;
    _identityQueue.clear();
    _client.close();
    if (_ownsTmdbClients) {
      for (final client in _activeClients.toList()) {
        client.close();
      }
      for (final client in _idleClients) {
        client.close();
      }
      _idleClients.clear();
    }
    _responses.clear();
    identityChanges.dispose();
  }

  static const pageSize = 50;
  static const tmdbLocalPageSize = 20;
  final _localTmdbLists = <String, _TmdbListCursor>{};
  final bool resolveIds;
  final Duration enrichmentBudget;
  final _identityGate = _NativeRequestGate(2);
  final _externalIds = <String, String?>{};
  // Tie completed hydration to the lifetime of each loaded card, rather than
  // to the bounded cross-page ID cache. Weak keys release unloaded cards.
  // A value identical to the key records a successful "no IMDb ID" lookup.
  final _hydratedItems = Expando<StremioMeta>();
  final _pendingIds = <String, Future<String?>>{};
  final _identityQueue = <String, StremioMeta>{};
  final _identityRetryAfter = <String, DateTime>{};
  final _prefetching = <String>{};
  int _identityWorkers = 0;
  final _catalogGate = _NativeRequestGate(4);

  /// IMDb identities make native titles work with watched state, metadata
  /// addons, and stream addons. Preserve TMDB-only titles when no mapping exists.
  Future<StremioMeta> resolveIdentity(StremioMeta meta) async {
    if (!meta.id.startsWith('tmdb:')) return meta;
    meta = withCachedIdentity(meta);
    if (meta.imdbId != null) {
      return StremioMeta.fromJson({...meta.toJson(), 'id': meta.imdbId});
    }
    final numericId = int.tryParse(meta.id.substring(5));
    if (numericId == null || numericId <= 0) return meta;
    final key = '${meta.type}:$numericId';
    Future<String?> load() async {
      final data = await _tmdbGet(
        '${meta.type == 'series' ? 'tv' : 'movie'}/$numericId/external_ids',
      );
      final raw = data['imdb_id'];
      final value = raw is String && RegExp(r'^tt[0-9]+$').hasMatch(raw)
          ? raw
          : null;
      if (_externalIds.length >= 2000) {
        _externalIds.remove(_externalIds.keys.first);
      }
      _externalIds[key] = value;
      _retainIdentity(meta, value);
      if (!_closed && value != null) identityChanges.value++;
      return value;
    }

    try {
      final id = _externalIds.containsKey(key)
          ? _externalIds[key]
          : await _pendingIds.putIfAbsent(
              key,
              () => load().whenComplete(() {
                _pendingIds.remove(key);
              }),
            );
      _retainIdentity(meta, id);
      if (id == null) return meta;
      return StremioMeta.fromJson({
        ...meta.toJson(),
        'id': id,
        'imdb_id': id,
        if (meta.poster == null)
          'poster': 'https://images.metahub.space/poster/medium/$id/img',
        if (meta.background == null)
          'background':
              'https://images.metahub.space/background/medium/$id/img',
      });
    } catch (_) {
      // Keep the catalog usable during an enrichment outage; retry on open.
      return meta;
    }
  }

  Future<List<StremioMeta>> _enrichPage(List<StremioMeta> items) async {
    final result = List<StremioMeta>.of(items);
    final elapsed = Stopwatch()..start();
    var next = 0;
    var finished = false;
    Future<void> worker() async {
      while (!_closed &&
          !finished &&
          next < items.length &&
          elapsed.elapsed < enrichmentBudget) {
        final index = next++;
        final resolved = await resolveIdentity(items[index]);
        if (!finished) result[index] = resolved;
      }
    }

    await Future.wait([
      worker(),
      worker(),
    ]).timeout(enrichmentBudget, onTimeout: () => <void>[]);
    finished = true;
    return result;
  }

  Future<CollectionSourcePage> fetch(CollectionCatalogSource source, int page) {
    if (source.provider == 'tmdb') return _tmdb(source, page);
    if (source.provider == 'trakt') return _trakt(source, page);
    throw CollectionSourceException(
      'Unsupported collection provider: ${source.provider}.',
    );
  }

  /// Browsing never waits for external IDs. Bounded enrichment runs
  /// separately, and listeners can refresh watched markers from the cache.
  Future<CollectionSourcePage> fetchPreview(
    CollectionCatalogSource source,
    int page,
  ) async {
    final result = source.provider == 'tmdb'
        ? await _tmdb(source, page, enrich: false)
        : source.provider == 'trakt'
        ? await _trakt(source, page, enrich: false)
        : throw CollectionSourceException(
            'Unsupported collection provider: ${source.provider}.',
          );
    prefetchIdentities(result.items);
    return result;
  }

  /// Keep optional work bounded and off the catalog path. Visible lists can
  /// offer their unresolved items again as capacity becomes available.
  void prefetchIdentities(List<StremioMeta> items) {
    if (!resolveIds || _closed) return;
    for (final item in items) {
      if (_identityQueue.length >= 128) break;
      if (!item.id.startsWith('tmdb:') || item.imdbId != null) continue;
      withCachedIdentity(item);
      if (_hydratedItems[item] != null) continue;
      final key = '${item.type}:${item.id.substring(5)}';
      if (_externalIds.containsKey(key) ||
          _prefetching.contains(key) ||
          (_identityRetryAfter[key]?.isAfter(DateTime.now()) ?? false)) {
        continue;
      }
      _identityQueue[key] = item;
    }
    while (_identityWorkers < 2 && _identityQueue.isNotEmpty) {
      _identityWorkers++;
      unawaited(_runIdentityWorker());
    }
  }

  Future<void> _runIdentityWorker() async {
    try {
      while (!_closed && _identityQueue.isNotEmpty) {
        final key = _identityQueue.keys.first;
        final item = _identityQueue.remove(key)!;
        _prefetching.add(key);
        try {
          await resolveIdentity(item);
          if (!_externalIds.containsKey(key)) {
            if (_identityRetryAfter.length >= 128) {
              _identityRetryAfter.remove(_identityRetryAfter.keys.first);
            }
            _identityRetryAfter[key] = DateTime.now().add(
              const Duration(seconds: 30),
            );
          }
        } finally {
          _prefetching.remove(key);
        }
      }
    } finally {
      _identityWorkers--;
    }
  }

  /// Preserve the catalog ID so late identity enrichment cannot move focus.
  StremioMeta withCachedIdentity(StremioMeta item) {
    if (!item.id.startsWith('tmdb:') || item.imdbId != null) return item;
    final retained = _hydratedItems[item];
    if (retained != null) return retained;
    final key = '${item.type}:${item.id.substring(5)}';
    if (!_externalIds.containsKey(key)) return item;
    return _retainIdentity(item, _externalIds[key]);
  }

  StremioMeta _retainIdentity(StremioMeta item, String? id) {
    final retained = _hydratedItems[item];
    if (retained != null && (id == null || retained.imdbId == id)) {
      return retained;
    }
    return _hydratedItems[item] = id == null
        ? item
        : StremioMeta.fromJson({
            ...item.toJson(),
            'id': item.id,
            'imdb_id': id,
          });
  }

  Future<http.Response> _readTmdb(
    Uri uri,
    Map<String, String> headers,
    Duration budget,
  ) async {
    final elapsed = Stopwatch()..start();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (_closed) throw const SocketException('Collection client is closed');
      final remaining = budget - elapsed.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('TMDB timed out');
      // Lease one client per active request: healthy connections are reused,
      // while a timeout can close its transport without cancelling siblings.
      final client = _idleClients.isEmpty
          ? _tmdbClientFactory()
          : _idleClients.removeLast();
      var reusable = false;
      _activeClients.add(client);
      final canRetry = attempt == 0 && remaining > retryDelay * 2;
      try {
        // Catalog requests can reserve a retry window. Identity lookups have
        // only three seconds: a healthy two-second response must still finish.
        // Fast failures can retry using whatever remains of that full budget.
        final identity = uri.path.endsWith('/external_ids');
        final limit = canRetry && !identity ? remaining ~/ 2 : remaining;
        final response = await (() async {
          final request = http.Request('GET', uri)..headers.addAll(headers);
          final streamed = await client.send(request);
          final bytes = <int>[];
          await for (final chunk in streamed.stream) {
            if (bytes.length + chunk.length > 4 * 1024 * 1024) {
              throw const CollectionSourceException(
                'TMDB response is too large.',
              );
            }
            bytes.addAll(chunk);
          }
          return http.Response.bytes(
            bytes,
            streamed.statusCode,
            headers: streamed.headers,
          );
        })().timeout(limit);
        reusable = response.statusCode == 200;
        if (response.statusCode == 429) {
          final seconds =
              int.tryParse(response.headers['retry-after'] ?? '') ?? 30;
          _rateLimitedUntil = DateTime.now().add(
            Duration(seconds: seconds.clamp(1, 300)),
          );
        }
        if (!canRetry ||
            !const {500, 502, 503, 504}.contains(response.statusCode)) {
          return response;
        }
      } on http.ClientException {
        if (!canRetry) rethrow;
      } on SocketException {
        if (!canRetry) rethrow;
      } on TimeoutException {
        if (!canRetry) rethrow;
      } finally {
        _activeClients.remove(client);
        if (_ownsTmdbClients) {
          if (reusable && !_closed && _idleClients.length < 6) {
            _idleClients.add(client);
          } else {
            client.close();
          }
        }
      }
      if (budget - elapsed.elapsed <= retryDelay) {
        throw TimeoutException('TMDB timed out');
      }
      await Future<void>.delayed(retryDelay);
    }
    throw const CollectionSourceException('TMDB could not load this list.');
  }

  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    final identity = uri.path.endsWith('/external_ids');
    final tmdb = uri.host == 'api.themoviedb.org';
    final budget = identity ? enrichmentBudget : requestBudget;
    Future<http.Response> request() {
      if (_closed) throw const SocketException('Collection client is closed');
      if (tmdb && (_rateLimitedUntil?.isAfter(DateTime.now()) ?? false)) {
        throw const CollectionSourceException(
          'TMDB is receiving too many requests. Wait a moment, then retry.',
        );
      }
      return tmdb
          ? _readTmdb(uri, headers, budget)
          : _client.get(uri, headers: headers).timeout(budget);
    }

    // Background metadata never occupies the catalog request gate.
    final response = identity
        ? await _identityGate.run(request, enrichmentBudget)
        : await _catalogGate.run(request, requestBudget);
    final provider = uri.host == 'api.themoviedb.org' ? 'TMDB' : 'Trakt';
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw CollectionSourceException(
        '$provider denied access. Check the app credentials or whether this list is private.',
      );
    }
    if (response.statusCode == 404) {
      throw CollectionSourceException(
        'This $provider list could not be found. Check its ID.',
      );
    }
    if (response.statusCode == 429) {
      throw CollectionSourceException(
        '$provider is receiving too many requests. Wait a moment, then retry.',
      );
    }
    if (response.statusCode != 200) {
      throw CollectionSourceException(
        '$provider could not load this list (HTTP ${response.statusCode}). Retry to continue.',
      );
    }
    return response;
  }

  Future<Map<String, dynamic>> _tmdbGet(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    if (_closed) throw const SocketException('Collection client is closed');
    if (path.endsWith('/external_ids')) return _loadTmdb(path, query);
    final key = jsonEncode([path, SplayTreeMap<String, String>.from(query)]);
    final cached = _responses.remove(key);
    if (cached != null) {
      if (cached.expires.isAfter(DateTime.now())) {
        _responses[key] = cached;
        return jsonDecode(cached.body) as Map<String, dynamic>;
      }
      _responseBytes -= cached.body.length * 2;
    }
    final pending = _pendingResponses[key];
    if (pending != null) {
      return jsonDecode(jsonEncode(await pending)) as Map<String, dynamic>;
    }
    final work = _loadTmdb(path, query);
    _pendingResponses[key] = work;
    try {
      final data = await work;
      if (!_closed) {
        final body = jsonEncode(data);
        _responses[key] = (
          expires: DateTime.now().add(const Duration(minutes: 5)),
          body: body,
        );
        _responseBytes += body.length * 2;
        while (_responses.length > 128 || _responseBytes > 8 * 1024 * 1024) {
          _responseBytes -=
              _responses.remove(_responses.keys.first)!.body.length * 2;
        }
      }
      return data;
    } finally {
      _pendingResponses.remove(key);
    }
  }

  Future<Map<String, dynamic>> _loadTmdb(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    if (_tmdbToken.trim().isEmpty) {
      throw const CollectionSourceException(
        'This build has no TMDB token. Rebuild with the local config or use a configured release.',
      );
    }
    final response = await _get(
      Uri.https('api.themoviedb.org', '/3/$path', {
        'language': 'en-US',
        ...query,
      }),
      {'Authorization': 'Bearer $_tmdbToken', 'Accept': 'application/json'},
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CollectionSourceException(
        'TMDB returned an invalid list. Retry to continue.',
      );
    }
    return decoded;
  }

  static const _filterNames = {
    'runtimeGte': 'with_runtime.gte',
    'runtimeLte': 'with_runtime.lte',
    'certificationCountry': 'certification_country',
    'certification': 'certification',
    'withCast': 'with_cast',
    'withCrew': 'with_crew',
    'withPeople': 'with_people',
    'monetization': 'with_watch_monetization_types',
    'withGenres': 'with_genres',
    'withoutGenres': 'without_genres',
    'voteAverageGte': 'vote_average.gte',
    'voteAverageLte': 'vote_average.lte',
    'voteCountGte': 'vote_count.gte',
    'withOriginalLanguage': 'with_original_language',
    'withOriginCountry': 'with_origin_country',
    'withKeywords': 'with_keywords',
    'withoutKeywords': 'without_keywords',
    'withCompanies': 'with_companies',
    'withoutCompanies': 'without_companies',
    'withNetworks': 'with_networks',
    'watchRegion': 'watch_region',
    'withWatchProviders': 'with_watch_providers',
    'withoutWatchProviders': 'without_watch_providers',
  };

  /// Query construction is shared with editor previews and request tests.
  static Map<String, String> discoverQuery(
    CollectionCatalogSource source,
    int page,
  ) {
    final tv = source.mediaType == 'tv' || source.tmdbSourceType == 'NETWORK';
    var sort = source.sortBy ?? 'popularity.desc';
    if (sort == 'original') sort = 'popularity.desc';
    sort = tv
        ? sort.replaceFirst('primary_release_date', 'first_air_date')
        : sort.replaceFirst('first_air_date', 'primary_release_date');
    final query = <String, String>{'page': '$page', 'sort_by': sort};
    for (final entry in source.filters.entries) {
      if (entry.value == null || '${entry.value}'.trim().isEmpty) continue;
      final key = switch (entry.key) {
        'releaseDateGte' =>
          tv ? 'first_air_date.gte' : 'primary_release_date.gte',
        'releaseDateLte' =>
          tv ? 'first_air_date.lte' : 'primary_release_date.lte',
        'year' => tv ? 'first_air_date_year' : 'primary_release_year',
        _ => _filterNames[entry.key],
      };
      if (key != null &&
          !(tv &&
              const {
                'certification_country',
                'certification',
                'with_cast',
                'with_crew',
                'with_people',
              }.contains(key))) {
        query[key] = '${entry.value}';
      }
    }
    if (source.tmdbSourceType == 'COMPANY') {
      query['with_companies'] = '${source.tmdbId}';
    }
    if (source.tmdbSourceType == 'NETWORK') {
      query['with_networks'] = '${source.tmdbId}';
      query.putIfAbsent(
        'first_air_date.lte',
        () => DateTime.now().toIso8601String().substring(0, 10),
      );
      query['with_status'] = '0|3|4';
    }
    if (query.containsKey('with_watch_providers') ||
        query.containsKey('without_watch_providers') ||
        query.containsKey('with_watch_monetization_types')) {
      query.putIfAbsent('watch_region', () => 'US');
    }
    if (query.containsKey('with_watch_providers')) {
      query.putIfAbsent(
        'with_watch_monetization_types',
        () => 'flatrate|free|ads|rent|buy',
      );
    }
    return query;
  }

  Future<CollectionSourcePage> _tmdb(
    CollectionCatalogSource source,
    int page, {
    bool enrich = true,
  }) async {
    final kind = source.tmdbSourceType;
    if (!const {
      'LIST',
      'COLLECTION',
      'COMPANY',
      'NETWORK',
      'DISCOVER',
      'PERSON',
      'DIRECTOR',
    }.contains(kind)) {
      throw CollectionSourceException(
        'Unsupported TMDB source type: ${kind ?? "missing"}.',
      );
    }
    if (kind != 'DISCOVER' && (source.tmdbId == null || source.tmdbId! <= 0)) {
      throw const CollectionSourceException(
        'This TMDB source needs a valid numeric ID. Edit the source to provide one.',
      );
    }
    final tv = source.mediaType == 'tv' || kind == 'NETWORK';
    final media = tv ? 'tv' : 'movie';
    final Map<String, dynamic> data;
    List<dynamic> raw;
    bool hasMore;
    if (kind == 'DISCOVER' || kind == 'COMPANY' || kind == 'NETWORK') {
      if (page > 500) {
        return const CollectionSourcePage(
          items: [],
          rawCount: 0,
          hasMore: false,
        );
      }
      data = await _tmdbGet('discover/$media', discoverQuery(source, page));
      raw = _list(data, 'results');
      hasMore = page < _int(data['total_pages'], fallback: page) && page < 500;
    } else {
      // These endpoints can return a whole list or filmography. Keep the raw
      // snapshot and expose small local pages before resolving IMDb identities.
      final batch = await _localTmdbPage(source, page, media);
      raw = batch.$1;
      hasMore = batch.$2;
    }
    final items = [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          if (_tmdbMeta(item, kind == 'COLLECTION' ? 'movie' : media)
              case final meta?)
            meta,
    ];
    return CollectionSourcePage(
      items: resolveIds && enrich
          ? await _enrichPage(items)
          : items.map(withCachedIdentity).toList(),
      rawCount: raw.length,
      hasMore: hasMore,
    );
  }

  Future<(List<dynamic>, bool)> _localTmdbPage(
    CollectionCatalogSource source,
    int page,
    String media,
  ) async {
    if (page < 1) {
      throw const CollectionSourceException('Invalid collection page.');
    }
    final cacheKey = jsonEncode(source.toJson());
    var cursor = _localTmdbLists.remove(cacheKey);
    // Rails and All-view readers share the same immutable catalog snapshot.
    // Expire idle snapshots, rather than resetting another reader's cursor.
    if (cursor == null ||
        (cursor.loading == null &&
            DateTime.now().difference(cursor.lastRead) >
                const Duration(minutes: 5))) {
      cursor = _TmdbListCursor();
    }
    cursor.lastRead = DateTime.now();
    if (_localTmdbLists.length >= 8) {
      _localTmdbLists.remove(_localTmdbLists.keys.first);
    }
    _localTmdbLists[cacheKey] = cursor;
    final end = page * tmdbLocalPageSize;
    // A sorted LIST must collect every raw remote page before exposing any
    // local page; otherwise a later high-ranking title can never move ahead
    // of titles already shown. IMDb enrichment still happens after slicing.
    final sortCompleteList =
        source.tmdbSourceType == 'LIST' &&
        source.sortBy != null &&
        source.sortBy != 'original';
    var windows = 0;
    while ((sortCompleteList || cursor.items.length < end) &&
        !cursor.exhausted) {
      if (windows >= 8) {
        throw const CollectionSourceException(
          'This list returned too few titles. Retry to continue.',
        );
      }
      if (sortCompleteList && cursor.remotePage > 50) {
        throw const CollectionSourceException(
          'This list is too large to sort here. Choose Original order to browse it.',
        );
      }
      final before = cursor.items.length;
      final pending = cursor.loading ??= _appendTmdbListPage(
        source,
        cursor,
        media,
      );
      try {
        await pending;
        windows = cursor.items.length == before ? windows + 1 : 0;
      } finally {
        if (identical(cursor.loading, pending)) cursor.loading = null;
      }
    }
    if (sortCompleteList && !cursor.sorted) {
      _sortTmdb(cursor.items, source.sortBy);
      cursor.sorted = true;
    }
    final start = (page - 1) * tmdbLocalPageSize;
    return (
      cursor.items.skip(start).take(tmdbLocalPageSize).toList(),
      cursor.items.length > end || !cursor.exhausted,
    );
  }

  Future<void> _appendTmdbListPage(
    CollectionCatalogSource source,
    _TmdbListCursor cursor,
    String media,
  ) async {
    final kind = source.tmdbSourceType;
    List<dynamic> raw;
    var hasMore = false;
    if (kind == 'LIST') {
      final data = await _tmdbGet('list/${source.tmdbId}', {
        'page': '${cursor.remotePage}',
      });
      raw = _list(data, 'items');
      hasMore =
          cursor.remotePage <
          _int(data['total_pages'], fallback: cursor.remotePage);
    } else if (kind == 'COLLECTION') {
      raw = _list(await _tmdbGet('collection/${source.tmdbId}'), 'parts');
    } else {
      final data = await _tmdbGet('person/${source.tmdbId}/combined_credits');
      raw = _list(data, kind == 'DIRECTOR' ? 'crew' : 'cast')
          .where(
            (item) =>
                item is Map &&
                item['media_type'] == media &&
                (kind != 'DIRECTOR' || item['job'] == 'Director'),
          )
          .toList();
    }
    if (kind != 'LIST') _sortTmdb(raw, source.sortBy);
    cursor.items.addAll(raw);
    cursor.remotePage++;
    cursor.exhausted = !hasMore;
  }

  static List<dynamic> _list(Map<String, dynamic> data, String key) {
    final items = data[key];
    if (items is! List) {
      throw const CollectionSourceException(
        'The provider returned an invalid list. Retry to continue.',
      );
    }
    return List<dynamic>.of(items);
  }

  static void _sortTmdb(List<dynamic> items, String? sort) {
    if (sort == null || sort == 'original') return;
    final field = switch (sort.split('.').first) {
      'primary_release_date' || 'first_air_date' => 'date',
      'vote_average' => 'vote_average',
      'vote_count' => 'vote_count',
      _ => 'popularity',
    };
    int compare(dynamic a, dynamic b) {
      if (a is! Map || b is! Map) return 0;
      if (field == 'date') {
        return '${a['release_date'] ?? a['first_air_date'] ?? ''}'.compareTo(
          '${b['release_date'] ?? b['first_air_date'] ?? ''}',
        );
      }
      return ((a[field] as num?) ?? 0).compareTo((b[field] as num?) ?? 0);
    }

    items.sort((a, b) => sort.endsWith('.asc') ? compare(a, b) : compare(b, a));
  }

  static StremioMeta? _tmdbMeta(
    Map<String, dynamic> raw,
    String fallbackMedia,
  ) {
    final id = _int(raw['id']);
    final title =
        raw['title'] ??
        raw['name'] ??
        raw['original_title'] ??
        raw['original_name'];
    if (id <= 0 || title is! String || title.trim().isEmpty) return null;
    final media = raw['media_type'] ?? fallbackMedia;
    if (media != 'tv' && media != 'movie') return null;
    final date = raw['release_date'] ?? raw['first_air_date'];
    String? image(Object? path, String size) =>
        path is String && path.startsWith('/')
        ? 'https://image.tmdb.org/t/p/$size$path'
        : null;
    return StremioMeta(
      id: 'tmdb:$id',
      type: media == 'tv' ? 'series' : 'movie',
      name: title,
      imdbId: raw['imdb_id'] as String?,
      poster: image(raw['poster_path'], 'w500'),
      background: image(raw['backdrop_path'], 'w1280'),
      description: raw['overview'] as String?,
      year: date is String && date.length >= 4 ? date.substring(0, 4) : null,
      imdbRating: (raw['vote_average'] as num?)?.toDouble(),
    );
  }

  Future<CollectionSourcePage> _trakt(
    CollectionCatalogSource source,
    int page, {
    bool enrich = true,
  }) async {
    if (source.traktListId == null || source.traktListId! <= 0) {
      throw const CollectionSourceException(
        'This Trakt source needs a valid numeric list ID.',
      );
    }
    final sort = source.sortBy ?? 'rank';
    final direction = source.sortHow ?? 'asc';
    if (!const {
          'rank',
          'added',
          'title',
          'released',
          'runtime',
          'popularity',
          'percentage',
          'votes',
        }.contains(sort) ||
        !const {'asc', 'desc'}.contains(direction)) {
      throw const CollectionSourceException(
        'This Trakt source has an unsupported sort option. Edit the source to choose a supported sort.',
      );
    }
    final type = source.type == 'series' ? 'show' : 'movie';
    final response = await _get(
      Uri.https('api.trakt.tv', '/lists/${source.traktListId}/items/$type', {
        'page': '$page',
        'limit': '$pageSize',
        'extended': 'full,images',
        'sort_by': sort,
        'sort_how': direction,
      }),
      {
        'trakt-api-key': kTraktClientId,
        'trakt-api-version': kTraktApiVersion,
        'Content-Type': 'application/json',
      },
    );
    final raw = jsonDecode(response.body);
    if (raw is! List) {
      throw const CollectionSourceException(
        'Trakt returned an invalid list. Retry to continue.',
      );
    }
    final pageCount = int.tryParse(
      response.headers['x-pagination-page-count'] ?? '',
    );
    final items = [
      for (final item in raw)
        if (item is Map<String, dynamic>)
          if (_traktMeta(item, type) case final meta?) meta,
    ];
    return CollectionSourcePage(
      items: resolveIds && enrich
          ? await _enrichPage(items)
          : items.map(withCachedIdentity).toList(),
      rawCount: raw.length,
      hasMore: pageCount != null ? page < pageCount : raw.length >= pageSize,
    );
  }

  static StremioMeta? _traktMeta(Map<String, dynamic> raw, String type) {
    final mapped = TraktItemTransformer.transformItem(raw, inferredType: type);
    if (mapped != null) return mapped;
    final content = raw[type];
    if (content is! Map) return null;
    final ids = content['ids'];
    if (ids is! Map || _int(ids['tmdb']) <= 0) return null;
    return _tmdbMeta({
      'id': ids['tmdb'],
      'title': content['title'],
      'overview': content['overview'],
      'vote_average': content['rating'],
      if (content['year'] != null) 'release_date': '${content['year']}-01-01',
    }, type == 'show' ? 'tv' : 'movie');
  }

  static int _int(Object? value, {int fallback = 0}) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;
}

/// Raw catalog pages only: enrichment is limited to the visible local batch.
class _TmdbListCursor {
  final items = <dynamic>[];
  int remotePage = 1;
  bool exhausted = false;
  DateTime lastRead = DateTime.now();
  bool sorted = false;
  Future<void>? loading;
}

/// Queued identity work expires too; an outage cannot build an unbounded tail.
class _NativeRequestGate {
  _NativeRequestGate(this.limit);
  final int limit;
  int active = 0;
  final waiters = Queue<Completer<void>>();
  Future<T> run<T>(Future<T> Function() operation, Duration budget) async {
    if (active >= limit) {
      final waiter = Completer<void>();
      waiters.add(waiter);
      try {
        await waiter.future.timeout(budget);
      } on TimeoutException {
        waiters.remove(waiter);
        rethrow;
      }
    } else {
      active++;
    }
    try {
      return await operation();
    } finally {
      if (waiters.isEmpty) {
        active--;
      } else {
        waiters.removeFirst().complete();
      }
    }
  }
}
