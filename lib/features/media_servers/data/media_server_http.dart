import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../models/media_server.dart';
import '../../../services/diagnostic_log.dart';
import '../models/media_server_errors.dart';

/// Request core shared by the Jellyfin/Emby and Plex clients (moved from the
/// original Jellyfin client). Redirects are refused so credentials and login
/// bodies are never forwarded, responses are capped, and failures become
/// typed [MediaServerException]s with the messages users already see.
class MediaServerHttp {
  MediaServerHttp(this._client, {required this.timeout});

  final http.Client _client;
  final Duration timeout;

  static const _maxResponseBytes = 8 * 1024 * 1024;

  static Uri normalizeBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const MediaServerException(
        'Enter an HTTP or HTTPS server URL without credentials or query parameters.',
      );
    }
    return uri.replace(path: '${uri.path.replaceAll(RegExp(r'/+$'), '')}/');
  }

  static Uri endpoint(
    String baseUrl,
    String path, [
    Map<String, String>? query,
  ]) => normalizeBaseUrl(baseUrl).resolve(path).replace(queryParameters: query);

  /// Sends one request and decodes a JSON object. Only [kind] and
  /// [operation] are recorded: never paths, queries, bodies or headers.
  /// [uri] and [headers] are built after the first authorization check, so
  /// a profile change wins over a malformed stored address or token.
  Future<Map<String, dynamic>> json(
    Uri Function() uri, {
    required Map<String, String> Function() headers,
    required MediaServerKind kind,
    required String operation,
    String method = 'GET',
    Map<String, dynamic>? body,
    Future<void> Function()? authorize,
    bool allowEmptyResponse = false,
    Duration? requestTimeout,
  }) async {
    final data = await decoded(
      uri,
      headers: headers,
      kind: kind,
      operation: operation,
      method: method,
      body: body,
      authorize: authorize,
      allowEmptyResponse: allowEmptyResponse,
      requestTimeout: requestTimeout,
    );
    return data as Map<String, dynamic>;
  }

  /// Like [json], for endpoints that answer with a JSON array.
  Future<List<dynamic>> jsonList(
    Uri Function() uri, {
    required Map<String, String> Function() headers,
    required MediaServerKind kind,
    required String operation,
    Future<void> Function()? authorize,
  }) async =>
      await decoded(
            uri,
            headers: headers,
            kind: kind,
            operation: operation,
            authorize: authorize,
            list: true,
          )
          as List<dynamic>;

  /// The decoded body: a JSON object, or a JSON array when [list] is set.
  Future<Object> decoded(
    Uri Function() uri, {
    required Map<String, String> Function() headers,
    required MediaServerKind kind,
    required String operation,
    String method = 'GET',
    Map<String, dynamic>? body,
    Future<void> Function()? authorize,
    bool allowEmptyResponse = false,
    Duration? requestTimeout,
    bool list = false,
  }) async {
    await authorize?.call();
    final request = http.Request(method, uri())
      // Never forward a session token or login body through an HTTP redirect.
      ..followRedirects = false
      ..headers.addAll(headers());
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final timer = Stopwatch()..start();
    int? status;
    var outcome = 'failed';
    try {
      final response = await (() async {
        final stream = await _client.send(request);
        status = stream.statusCode;
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          bytes.addAll(chunk);
          if (bytes.length > _maxResponseBytes) {
            throw const MediaServerException(
              'The server response is too large.',
            );
          }
        }
        return http.Response.bytes(
          bytes,
          stream.statusCode,
          headers: stream.headers,
        );
      })().timeout(requestTimeout ?? timeout);
      await authorize?.call();
      checkStatus(response.statusCode);
      if (allowEmptyResponse && response.bodyBytes.isEmpty) {
        outcome = 'ok';
        return list ? <dynamic>[] : <String, dynamic>{};
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (list ? data is! List : data is! Map<String, dynamic>) {
        throw const FormatException();
      }
      outcome = 'ok';
      return data as Object;
    } on MediaServerException {
      rethrow;
    } on TimeoutException {
      outcome = 'timeout';
      throw const MediaServerTimeout(
        'Server timed out. Check its address and network connection.',
      );
    } on FormatException {
      outcome = 'invalid_response';
      throw const MediaServerException(
        'The server returned an invalid response. Check the server URL.',
      );
    } on http.ClientException {
      outcome = 'network_error';
      throw const MediaServerUnreachable(
        'Cannot reach the server. Check its address and network connection.',
      );
    } finally {
      DiagnosticLog.instance.recordEvent(
        source: 'media_server',
        event: 'request',
        fields: {
          'kind': DiagnosticLabel(kind.name),
          'operation': DiagnosticLabel(operation),
          'status': status,
          'outcome': DiagnosticLabel(outcome),
          'elapsed_ms': timer.elapsedMilliseconds,
        },
      );
    }
  }

  /// Maps a non-success status to the shared typed errors.
  static void checkStatus(int status) {
    if (status == 401) {
      throw const MediaServerAuthError(
        'Sign-in expired or credentials are incorrect. Reconnect this server.',
        status: 401,
      );
    }
    if (status == 403) {
      throw const MediaServerAuthError(
        'This server user does not have permission to play this content.',
        status: 403,
      );
    }
    if (status >= 300 && status < 400) {
      throw MediaServerHttpError(
        'The server redirected this request. Use its final URL, including any base path.',
        status: status,
      );
    }
    if (status < 200 || status >= 300) {
      throw MediaServerHttpError(
        'The server could not complete the request (HTTP $status).',
        status: status,
      );
    }
  }

  /// Authenticated, bounded thumbnail bytes, or null when the server has no
  /// image. Never forwards credentials on redirects.
  Future<Uint8List?> image(
    Uri Function() uri, {
    required Map<String, String> Function() headers,
    Future<void> Function()? authorize,
  }) async {
    await authorize?.call();
    final request = http.Request('GET', uri())
      ..followRedirects = false
      ..headers.addAll(headers());
    final bytes = await (() async {
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        await response.stream.listen(null).cancel();
        return null;
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (buffer.length + chunk.length > 2 * 1024 * 1024) {
          throw const MediaServerException('Server image is too large.');
        }
        buffer.add(chunk);
      }
      return buffer.takeBytes();
    })().timeout(timeout);
    await authorize?.call();
    return bytes;
  }
}
