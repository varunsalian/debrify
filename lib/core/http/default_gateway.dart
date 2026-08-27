import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpDate, SocketException;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'gateway.dart';
import '../../utils/json_isolate.dart';

/// The one place in the app that talks to `package:http`.
///
/// Holds one pooled [http.Client] rather than the 20 the services used to
/// construct between them, applies a default timeout to every request (12
/// files had none at all), and retries only what is worth retrying.
///
/// Injected, never reached for: the composition root builds one and hands it
/// down. The [client] parameter is the whole test seam — pass a
/// `MockClient` from `package:http/testing.dart` and no socket is opened.
class DefaultHttpGateway implements HttpGateway {
  final http.Client _client;
  final String _userAgent;
  final Duration _defaultTimeout;
  final RetryPolicy _defaultRetry;

  /// Injected so tests advance time instead of spending it. Production passes
  /// nothing and gets a real delay.
  final Future<void> Function(Duration) _sleep;

  DefaultHttpGateway({
    http.Client? client,
    required String userAgent,
    Duration defaultTimeout = const Duration(seconds: 15),
    RetryPolicy defaultRetry = RetryPolicy.standard,
    Future<void> Function(Duration)? sleep,
  }) : _client = client ?? http.Client(),
       _userAgent = userAgent,
       _defaultTimeout = defaultTimeout,
       _defaultRetry = defaultRetry,
       _sleep = sleep ?? _realSleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  @override
  Future<HttpResponse> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk = false,
  }) => _run(
    url,
    () => http.Request('GET', url)..headers.addAll(_headers(headers)),
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
    expectOk: expectOk,
  );

  @override
  Future<HttpResponse> post(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk = false,
  }) => _run(
    url,
    () => _bodyRequest('POST', url, body, encoding, headers),
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
    expectOk: expectOk,
  );

  @override
  Future<HttpResponse> put(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk = false,
  }) => _run(
    url,
    () => _bodyRequest('PUT', url, body, encoding, headers),
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
    expectOk: expectOk,
  );

  @override
  Future<HttpResponse> delete(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk = false,
  }) => _run(
    url,
    () => _bodyRequest('DELETE', url, body, encoding, headers),
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
    expectOk: expectOk,
  );

  @override
  Future<HttpResponse> patch(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk = false,
  }) => _run(
    url,
    () => _bodyRequest('PATCH', url, body, encoding, headers),
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
    expectOk: expectOk,
  );

  @override
  Future<HttpResponse> head(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
  }) => _run(
    url,
    () => http.Request('HEAD', url)
      ..headers.addAll(_headers(headers))
      ..followRedirects = false,
    timeout: timeout,
    retry: retry,
    maxBytes: null,
    expectOk: false,
  );

  /// Large payloads decode on a worker isolate — an Xtream stream list runs to
  /// tens of megabytes, and parsing that on the UI isolate is what drops frames
  /// on a Mi-Box-class CPU. [decodeJsonAsync] already owns that threshold.
  @override
  Future<dynamic> decodeJson(String source) => decodeJsonAsync(source);

  @override
  void close() => _client.close();

  Map<String, String> _headers(Map<String, String>? extra) {
    final merged = <String, String>{'user-agent': _userAgent};
    if (extra != null) {
      for (final entry in extra.entries) {
        merged[entry.key.toLowerCase()] = entry.value;
      }
    }
    return merged;
  }

  http.Request _bodyRequest(
    String method,
    Uri url,
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
  ) {
    final request = http.Request(method, url)
      ..headers.addAll(_headers(headers));
    if (encoding != null) request.encoding = encoding;
    switch (body) {
      case null:
        break;
      case String():
        request.body = body;
      case List<int>():
        request.bodyBytes = body;
      case Map<String, String>():
        request.bodyFields = body;
      default:
        throw ArgumentError.value(body, 'body', 'unsupported body type');
    }
    return request;
  }

  /// One request, retried per [retry]. Each attempt builds a fresh
  /// [http.BaseRequest] — a request that has been sent cannot be sent again.
  Future<HttpResponse> _run(
    Uri url,
    http.BaseRequest Function() build, {
    required Duration? timeout,
    required RetryPolicy? retry,
    required int? maxBytes,
    required bool expectOk,
  }) async {
    final limit = timeout ?? _defaultTimeout;
    final policy = retry ?? _defaultRetry;
    final attempts = policy.attempts < 1 ? 1 : policy.attempts;

    for (var attempt = 1; ; attempt++) {
      final last = attempt >= attempts;
      try {
        final response = await _attempt(url, build(), limit, maxBytes, attempt);

        if (!response.ok && !last && _retryableStatus(response, policy)) {
          await _sleep(_delayFor(response, policy, attempt));
          continue;
        }
        if (expectOk && !response.ok) {
          throw HttpStatusFailure(url, response, attempt);
        }
        return response;
      } on HttpTooLargeFailure {
        rethrow;
      } on HttpStatusFailure {
        rethrow;
      } on HttpFailure {
        if (last) rethrow;
        await _sleep(policy.backoffFor(attempt));
      }
    }
  }

  Future<HttpResponse> _attempt(
    Uri url,
    http.BaseRequest request,
    Duration limit,
    int? maxBytes,
    int attempt,
  ) async {
    try {
      return await _sendAndRead(request, maxBytes, attempt).timeout(limit);
    } on TimeoutException {
      throw HttpTimeoutFailure(url, limit, attempt);
    } on http.ClientException catch (e) {
      throw HttpNetworkFailure(url, e, attempt);
    } on SocketException catch (e) {
      throw HttpNetworkFailure(url, e, attempt);
    } on HandshakeException catch (e) {
      throw HttpNetworkFailure(url, e, attempt);
    }
  }

  Future<HttpResponse> _sendAndRead(
    http.BaseRequest request,
    int? maxBytes,
    int attempt,
  ) async {
    final streamed = await _client.send(request);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (maxBytes != null && builder.length > maxBytes) {
        throw HttpTooLargeFailure(request.url, maxBytes, attempt);
      }
    }
    return HttpResponse(
      statusCode: streamed.statusCode,
      bodyBytes: Uint8List.fromList(builder.takeBytes()),
      headers: streamed.headers,
      url: request.url,
      attempts: attempt,
    );
  }

  bool _retryableStatus(HttpResponse response, RetryPolicy policy) {
    if (response.statusCode == 429) return true;
    if (response.statusCode == 503) return true;
    return policy.retryServerErrors && response.statusCode >= 500;
  }

  Duration _delayFor(HttpResponse response, RetryPolicy policy, int attempt) {
    final backoff = policy.backoffFor(attempt);
    if (!policy.honorRetryAfter) return backoff;
    final after = _retryAfter(response.headers['retry-after']);
    if (after == null) return backoff;
    return after > policy.maxRetryAfter ? policy.maxRetryAfter : after;
  }

  /// `Retry-After` is either a count of seconds or an HTTP date.
  static Duration? _retryAfter(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return seconds <= 0 ? Duration.zero : Duration(seconds: seconds);
    }
    final date = _parseHttpDate(trimmed);
    if (date == null) return null;
    final delta = date.difference(DateTime.now().toUtc());
    return delta.isNegative ? Duration.zero : delta;
  }

  static DateTime? _parseHttpDate(String raw) {
    try {
      return HttpDate.parse(raw).toUtc();
    } catch (_) {
      return null;
    }
  }
}
