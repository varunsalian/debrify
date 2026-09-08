import 'diagnostic_log.dart';
import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:typed_data';
import '../utils/json_isolate.dart';

import 'package:http/http.dart' as http;

import '../models/stremio_addon.dart';
import 'tmdb_http_client.dart';

class TmdbMetadataException implements Exception {
  const TmdbMetadataException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef TmdbIdentity = ({String type, int id});

/// Public metadata only. Cache keys contain the complete query (including
/// locale); no user tokens or profile state are cached here. Each request owns
/// its client so timeout cancellation closes the actual transport.
class TmdbMetadataRepository {
  TmdbMetadataRepository({
    String token = const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN'),
    http.Client Function()? clientFactory,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 12),
  }) : _token = token,
       _clientFactory =
           clientFactory ?? (() => TmdbHttpClient(dnsCache: _dnsCache)),
       _now = now ?? DateTime.now;

  static final instance = TmdbMetadataRepository();
  static final _dnsCache = TmdbDnsCache();
  final String _token;
  final http.Client Function() _clientFactory;
  final DateTime Function() _now;
  final Duration timeout;
  final _cache =
      <String, ({DateTime expires, Map<String, dynamic> data, int bytes})>{};
  final _pending = <String, Future<Map<String, dynamic>>>{};
  static final Object _heroPriorityKey = Object();
  static Future<T> withHeroPriority<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_heroPriorityKey: true});
  final _waiters = Queue<({String key, Completer<void> ready})>();
  final _heroRequests = <String>{};
  int _heroBurst = 0;
  final _relevance = <String, List<bool Function()>>{};
  int _active = 0;
  int _cacheBytes = 0;
  DateTime? _retryAfter;

  bool get configured => _token.trim().isNotEmpty;

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
    bool Function()? isRelevant,
  ]) {
    if (!configured) {
      return Future.error(
        const TmdbMetadataException('TMDB is unavailable in this build.'),
      );
    }
    if (!RegExp(r'^[a-zA-Z0-9_/-]+$').hasMatch(path) || path.contains('..')) {
      return Future.error(
        const TmdbMetadataException('Invalid TMDB resource.'),
      );
    }
    final sorted = SplayTreeMap<String, String>.from(query);
    final uri = Uri.https('api.themoviedb.org', '/3/$path', sorted);
    final key = uri.toString();
    final cached = _cache.remove(key);
    if (cached != null && cached.expires.isAfter(_now())) {
      _cache[key] = cached;
      return Future.value(_copy(cached.data));
    }
    if (cached != null) _cacheBytes -= cached.bytes;
    if (Zone.current[_heroPriorityKey] == true) _heroRequests.add(key);
    final pending = _pending[key];
    if (pending != null) {
      _relevance[key]?.add(isRelevant ?? () => true);
      return pending.then(_copy);
    }
    if (_pending.length >= 128) {
      _heroRequests.remove(key);
      return Future.error(
        const TmdbMetadataException('Metadata is busy. Try again shortly.'),
      );
    }
    _relevance[key] = [isRelevant ?? () => true];
    final request = _fetch(uri)
        .then((result) {
          _cache[key] = (
            expires: _now().add(const Duration(minutes: 15)),
            data: result.data,
            bytes: result.bytes,
          );
          _cacheBytes += result.bytes;
          while (_cache.length > 128 || _cacheBytes > 8 * 1024 * 1024) {
            final evicted = _cache.remove(_cache.keys.first)!;
            _cacheBytes -= evicted.bytes;
          }
          return result.data;
        })
        .whenComplete(() {
          _pending.remove(key);
          _relevance.remove(key);
          _heroRequests.remove(key);
        });
    _pending[key] = request;
    return request.then(_copy);
  }

  static Object? _clone(Object? value) => switch (value) {
    Map<String, dynamic> value => value.map(
      (key, item) => MapEntry(key, _clone(item)),
    ),
    List value => value.map(_clone).toList(),
    _ => value,
  };
  static Map<String, dynamic> _copy(Map<String, dynamic> data) =>
      _clone(data) as Map<String, dynamic>;

  Future<http.Response> _read(http.Client client, Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $_token',
        'Accept': 'application/json',
      });
    final response = await client.send(request);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const TmdbMetadataException('TMDB response is too large.');
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(
      bytes.takeBytes(),
      response.statusCode,
      headers: response.headers,
    );
  }

  Future<({Map<String, dynamic> data, int bytes})> _fetch(Uri uri) async {
    final timing = Stopwatch()..start();
    if (_active >= 4) {
      final ready = Completer<void>();
      _waiters.add((key: uri.toString(), ready: ready));
      await ready.future;
    } else {
      _active++;
    }
    final queueMs = timing.elapsedMilliseconds;
    var success = false;
    var failure = 'none';
    int? status;
    try {
      if (!(_relevance[uri.toString()]?.any((check) => check()) ?? true)) {
        failure = 'cancelled';
        throw const TmdbMetadataException(
          'Metadata request is no longer needed.',
        );
      }
      if (_retryAfter?.isAfter(_now()) ?? false) {
        failure = 'rate_limited';
        throw const TmdbMetadataException('TMDB is busy. Try again shortly.');
      }
      final response = await _readWithRetry(uri);
      status = response.statusCode;
      if (response.statusCode == 429) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 30;
        _retryAfter = _now().add(Duration(seconds: seconds.clamp(1, 300)));
      }
      if (response.statusCode != 200) {
        failure = 'http_status';
        throw TmdbMetadataException(
          'TMDB could not load metadata (${response.statusCode}).',
        );
      }
      if (response.bodyBytes.length > 4 * 1024 * 1024) {
        throw const TmdbMetadataException('TMDB response is too large.');
      }
      final decoded = await decodeJsonAsync(response.body);
      final data =
          decoded is List &&
              const {
                '/3/configuration/languages',
                '/3/configuration/countries',
              }.contains(uri.path)
          ? <String, dynamic>{'results': decoded}
          : decoded;
      if (data is! Map<String, dynamic>) {
        throw const TmdbMetadataException('TMDB returned invalid metadata.');
      }
      success = true;
      return (data: data, bytes: response.bodyBytes.length);
    } on TimeoutException {
      failure = 'timeout';
      throw const TmdbMetadataException('TMDB timed out. Try again.');
    } catch (error) {
      if (failure == 'none') {
        failure = error is HandshakeException ? 'tls' :
            error is SocketException ? 'socket' :
            error is http.ClientException ? 'transport' :
            error is FormatException ? 'decode' : 'invalid_response';
      }
      rethrow;
    } finally {
      DiagnosticLog.instance.recordEvent(source: 'metadata', event: 'tmdb_request',
        fields: {'queue_ms': queueMs, 'work_ms': timing.elapsedMilliseconds - queueMs,
          'success': success, 'waiting': _waiters.length,
          'failure': DiagnosticLabel(failure), 'status': status,
          'hero': _heroRequests.contains(uri.toString()),
          'kind': DiagnosticLabel(uri.path.startsWith('/3/find/') ? 'identity' : 'metadata')});
      if (_waiters.isNotEmpty) {
        // Prefer heroes, but give ordinary cards a turn after two heroes.
        final heroes = _waiters.where((w) => _heroRequests.contains(w.key));
        final normal = _waiters.where((w) => !_heroRequests.contains(w.key));
        final next = heroes.isNotEmpty && (_heroBurst < 2 || normal.isEmpty)
            ? heroes.first : normal.isNotEmpty ? normal.first : _waiters.first;
        _heroBurst = _heroRequests.contains(next.key) ? _heroBurst + 1 : 0;
        _waiters.remove(next);
        next.ready.complete();
      } else {
        _active--;
      }
    }
  }

  Future<http.Response> _readWithRetry(Uri uri) async {
    final elapsed = Stopwatch()..start();
    for (var attempt = 0; attempt < 2; attempt++) {
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('TMDB timed out');
      final client = _clientFactory();
      try {
        return await _read(client, uri).timeout(remaining);
      } on http.ClientException {
        // These are public, idempotent GETs. A reset on a cold connection may
        // succeed immediately on a fresh transport; never retry API errors,
        // timeouts, or a request whose subscribers have left.
        if (attempt == 1 ||
            elapsed.elapsed >= timeout ||
            !(_relevance[uri.toString()]?.any((check) => check()) ?? true)) {
          rethrow;
        }
      } finally {
        client.close();
      }
    }
    throw const TmdbMetadataException('TMDB connection failed. Try again.');
  }

  Future<TmdbIdentity?> identify(
    StremioMeta item, {
    bool Function()? isRelevant,
  }) async {
    final type = switch (item.type) {
      'movie' => 'movie',
      'series' => 'tv',
      _ => null,
    };
    if (type == null) return null;
    final direct = RegExp(r'^tmdb:(\d+)$').firstMatch(item.id);
    if (direct != null) {
      final id = int.tryParse(direct.group(1)!);
      return id != null && id > 0 ? (type: type, id: id) : null;
    }
    final imdb = item.imdbId ?? item.id;
    if (!RegExp(r'^tt\d+$').hasMatch(imdb)) return null;
    final data = await get('find/$imdb', {
      'external_source': 'imdb_id',
    }, isRelevant);
    final results = data[type == 'movie' ? 'movie_results' : 'tv_results'];
    if (results is! List || results.length != 1) return null;
    final row = results.first;
    final id = row is Map ? row['id'] : null;
    return id is int && id > 0 ? (type: type, id: id) : null;
  }

  Future<Map<String, dynamic>> details(
    TmdbIdentity identity, {
    required String language,
    String imageLanguage = 'en',
    String append = 'images,credits,videos,recommendations',
    bool Function()? isRelevant,
  }) => get('${identity.type}/${identity.id}', {
    'language': language,
    'include_image_language': '$imageLanguage,en,null',
    'append_to_response': append,
  }, isRelevant);

  static String? image(Object? path, {String size = 'w500'}) =>
      path is String &&
          path.startsWith('/') &&
          !path.startsWith('//') &&
          !path.contains('..') &&
          RegExp(r'^/[a-zA-Z0-9_.-]+$').hasMatch(path)
      ? 'https://image.tmdb.org/t/p/$size$path'
      : null;
}
