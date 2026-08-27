import 'dart:convert';
import 'dart:typed_data';

/// The app's outbound HTTP surface, as the rest of the app sees it.
///
/// Pure Dart on purpose: nothing here names `package:http`, so a caller that
/// depends on this port cannot reach the underlying client, and swapping the
/// transport is an infrastructure concern rather than a call-site edit.
///
/// Every request carries a timeout and a retry policy — the two things 38
/// files used to decide for themselves, when they decided at all. Defaults
/// live on the implementation so a call site only names what it needs to
/// differ on.
abstract interface class HttpGateway {
  Future<HttpResponse> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk,
  });

  Future<HttpResponse> post(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk,
  });

  Future<HttpResponse> put(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk,
  });

  Future<HttpResponse> delete(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk,
  });

  Future<HttpResponse> patch(
    Uri url, {
    Object? body,
    Encoding? encoding,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
    bool expectOk,
  });

  /// HEAD does not follow redirects: probes that care about the final URL
  /// (stream validation) walk the chain themselves so they judge the hop they
  /// actually landed on.
  Future<HttpResponse> head(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
  });

  /// Parses a JSON payload. On the interface rather than in [HttpGatewayJson]
  /// because *where* it parses is a transport decision: large catalog and
  /// stream-list payloads must decode off the UI isolate or weak TV CPUs drop
  /// frames, and only the implementation knows how to get there.
  Future<dynamic> decodeJson(String source);

  /// Releases the pooled connections. The composition root owns this; a
  /// feature that was handed a gateway must not close it.
  void close();
}

/// The verbs [HttpGateway.send] dispatches on.
enum HttpMethod { get, post, put, patch, delete }

/// Turns a decoded JSON tree into a model. Every model in `lib/models/` that
/// already has a `fromJson` satisfies this as a tear-off.
typedef JsonDecoder<T> = T Function(dynamic json);

/// Typed requests, built on the raw five so an implementation — or a fake —
/// only has to provide those.
///
/// These imply `expectOk: true`: a non-2xx has no body worth decoding, so the
/// status surfaces as [HttpStatusFailure] instead of arriving as a model-shaped
/// cast error three frames later.
extension HttpGatewayJson on HttpGateway {
  /// One typed call, method included — the shape of a hand-written
  /// `api<T, K>({ method, url, body })` helper.
  ///
  /// [decode] is not ceremony that a TypeScript version gets to skip: `as K`
  /// there is an erased compile-time assertion, so a backend that changes a
  /// field's type hands the caller a mislabelled object that fails somewhere
  /// else entirely. Dart's generics are reified, so `jsonDecode(body) as K`
  /// throws at the cast. Naming the decoder is what turns that into a
  /// [HttpDecodeFailure] at the boundary, with the URL attached.
  ///
  /// Defaults to GET rather than POST: this app reads far more than it writes.
  Future<K> send<K>({
    required Uri url,
    required JsonDecoder<K> decode,
    HttpMethod method = HttpMethod.get,
    Object? json,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) async {
    final payload = json != null ? jsonEncode(json) : body;
    final merged = _jsonHeaders(json, headers);
    final response = await switch (method) {
      HttpMethod.get => get(
        url,
        headers: headers,
        timeout: timeout,
        retry: retry,
        maxBytes: maxBytes,
        expectOk: true,
      ),
      HttpMethod.post => post(
        url,
        body: payload,
        headers: merged,
        timeout: timeout,
        retry: retry,
        maxBytes: maxBytes,
        expectOk: true,
      ),
      HttpMethod.put => put(
        url,
        body: payload,
        headers: merged,
        timeout: timeout,
        retry: retry,
        maxBytes: maxBytes,
        expectOk: true,
      ),
      HttpMethod.patch => patch(
        url,
        body: payload,
        headers: merged,
        timeout: timeout,
        retry: retry,
        maxBytes: maxBytes,
        expectOk: true,
      ),
      HttpMethod.delete => delete(
        url,
        body: payload,
        headers: merged,
        timeout: timeout,
        retry: retry,
        maxBytes: maxBytes,
        expectOk: true,
      ),
    };
    return _decodeBody(response, decode);
  }

  Future<T> getJson<T>(
    Uri url,
    JsonDecoder<T> decode, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) async => _decodeBody(
    await get(
      url,
      headers: headers,
      timeout: timeout,
      retry: retry,
      maxBytes: maxBytes,
      expectOk: true,
    ),
    decode,
  );

  /// A JSON array of objects, which is most of what the debrid and catalog
  /// APIs return.
  Future<List<T>> getJsonList<T>(
    Uri url,
    T Function(Map<String, dynamic>) item, {
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) => getJson(
    url,
    (json) => (json as List).cast<Map<String, dynamic>>().map(item).toList(),
    headers: headers,
    timeout: timeout,
    retry: retry,
    maxBytes: maxBytes,
  );

  /// [json] is encoded and `content-type: application/json` is set, replacing
  /// the `jsonEncode(...)` plus hand-written header that 31 call sites pair up
  /// today. Pass [body] instead for form or raw payloads.
  Future<T> postJson<T>(
    Uri url,
    JsonDecoder<T> decode, {
    Object? json,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) async => _decodeBody(
    await post(
      url,
      body: json != null ? jsonEncode(json) : body,
      headers: _jsonHeaders(json, headers),
      timeout: timeout,
      retry: retry,
      maxBytes: maxBytes,
      expectOk: true,
    ),
    decode,
  );

  Future<T> putJson<T>(
    Uri url,
    JsonDecoder<T> decode, {
    Object? json,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) async => _decodeBody(
    await put(
      url,
      body: json != null ? jsonEncode(json) : body,
      headers: _jsonHeaders(json, headers),
      timeout: timeout,
      retry: retry,
      maxBytes: maxBytes,
      expectOk: true,
    ),
    decode,
  );

  Future<T> deleteJson<T>(
    Uri url,
    JsonDecoder<T> decode, {
    Object? json,
    Object? body,
    Map<String, String>? headers,
    Duration? timeout,
    RetryPolicy? retry,
    int? maxBytes,
  }) async => _decodeBody(
    await delete(
      url,
      body: json != null ? jsonEncode(json) : body,
      headers: _jsonHeaders(json, headers),
      timeout: timeout,
      retry: retry,
      maxBytes: maxBytes,
      expectOk: true,
    ),
    decode,
  );

  Map<String, String> _jsonHeaders(Object? json, Map<String, String>? headers) {
    if (json == null) return headers ?? const {};
    return {'content-type': 'application/json', ...?headers};
  }

  /// Both halves fail the same way. A dead panel answering 200 with an HTML
  /// error page is a [FormatException]; a live API that changed a field's type
  /// is a cast error inside [decode]. Neither is worth a distinct catch at the
  /// call site.
  Future<T> _decodeBody<T>(HttpResponse response, JsonDecoder<T> decode) async {
    // 204, and the 200-with-no-body that several debrid deletes answer with.
    // Parsing "" throws, so the decoder is handed null and decides what an
    // absent payload means for its own type.
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      try {
        return decode(null);
      } catch (e) {
        throw HttpDecodeFailure(response.url, e, response.attempts);
      }
    }
    dynamic tree;
    try {
      tree = await decodeJson(response.body);
    } catch (e) {
      throw HttpDecodeFailure(response.url, e, response.attempts);
    }
    try {
      return decode(tree);
    } catch (e) {
      throw HttpDecodeFailure(response.url, e, response.attempts);
    }
  }
}

/// One response, decoupled from the transport's own type.
class HttpResponse {
  final int statusCode;
  final Uint8List bodyBytes;

  /// Lower-cased header names, as every HTTP implementation normalises them.
  final Map<String, String> headers;

  /// The URL that actually answered, after any redirects.
  final Uri url;

  /// Requests actually made to produce this, retries included.
  final int attempts;

  const HttpResponse({
    required this.statusCode,
    required this.bodyBytes,
    required this.headers,
    required this.url,
    this.attempts = 1,
  });

  bool get ok => statusCode >= 200 && statusCode < 300;

  /// Bytes actually received.
  int get length => bodyBytes.length;

  /// What the server claimed in `content-length`, which is the only size
  /// signal a HEAD probe gets. Null when unset or unparseable.
  int? get declaredContentLength =>
      int.tryParse(headers['content-length'] ?? '');

  /// Decoded with the charset the server declared, falling back to UTF-8 in
  /// malformed-tolerant mode. Panels and scrapers routinely serve a stray
  /// invalid byte inside an otherwise fine payload, and throwing on those
  /// loses the whole response.
  String get body {
    final charset = _charset;
    if (charset == 'iso-8859-1' || charset == 'latin1') {
      return latin1.decode(bodyBytes, allowInvalid: true);
    }
    return utf8.decode(bodyBytes, allowMalformed: true);
  }

  String? get _charset {
    final type = headers['content-type'];
    if (type == null) return null;
    for (final part in type.split(';')) {
      final trimmed = part.trim().toLowerCase();
      if (trimmed.startsWith('charset=')) {
        return trimmed.substring(8).replaceAll('"', '').trim();
      }
    }
    return null;
  }
}

/// How many times an attempt is worth repeating, and how long to wait between.
///
/// Only transient failures consume an attempt: a timeout, a dropped socket, a
/// 5xx, or a 429. A 4xx is the server's real answer and returns immediately
/// rather than burning the budget on a result that will not change.
class RetryPolicy {
  /// Total attempts including the first. 1 disables retrying.
  final int attempts;

  final Duration initialBackoff;

  /// Applied per subsequent attempt, capped at [maxBackoff].
  final double multiplier;

  final Duration maxBackoff;

  /// Whether a 5xx is worth repeating. Turn off for endpoints where a 500
  /// means "this request is malformed" rather than "this server is unwell".
  final bool retryServerErrors;

  /// Whether a `Retry-After` on a 429/503 overrides the computed backoff,
  /// capped at [maxRetryAfter] so a hostile header cannot stall a play.
  final bool honorRetryAfter;

  final Duration maxRetryAfter;

  const RetryPolicy({
    this.attempts = 3,
    this.initialBackoff = const Duration(milliseconds: 500),
    this.multiplier = 2.0,
    this.maxBackoff = const Duration(seconds: 4),
    this.retryServerErrors = true,
    this.honorRetryAfter = true,
    this.maxRetryAfter = const Duration(seconds: 10),
  });

  /// One shot. For anything the user is actively waiting on where a slow
  /// answer is worse than a fast failure.
  static const none = RetryPolicy(attempts: 1);

  /// The default: three attempts, 500ms then 1s between them.
  static const standard = RetryPolicy();

  /// For large payloads over flaky panels — Xtream stream lists run to tens of
  /// megabytes and CDNs drop them mid-transfer under load.
  static const patient = RetryPolicy(
    attempts: 5,
    initialBackoff: Duration(seconds: 1),
    maxBackoff: Duration(seconds: 15),
  );

  /// Wait before attempt number [attempt] + 1, where [attempt] is 1-based.
  Duration backoffFor(int attempt) {
    var ms = initialBackoff.inMilliseconds.toDouble();
    for (var i = 1; i < attempt; i++) {
      ms *= multiplier;
      if (ms >= maxBackoff.inMilliseconds) return maxBackoff;
    }
    return Duration(milliseconds: ms.round());
  }
}

/// Everything the gateway can fail with, as one closed set.
///
/// Callers switch on this instead of catching `TimeoutException`,
/// `SocketException` and `http.ClientException` separately — the three
/// spellings of "the network did not cooperate" that every service currently
/// has to know about for itself.
sealed class HttpFailure implements Exception {
  final Uri url;

  /// Attempts actually made, so a log can tell "failed once" from "failed
  /// after the whole retry budget".
  final int attempts;

  const HttpFailure(this.url, this.attempts);

  String get message;

  @override
  String toString() =>
      '$runtimeType($url, after $attempts attempt(s)): $message';
}

/// The request exceeded its timeout — on connect, on headers, or partway
/// through the body.
final class HttpTimeoutFailure extends HttpFailure {
  final Duration timeout;

  const HttpTimeoutFailure(super.url, this.timeout, super.attempts);

  @override
  String get message => 'no answer within ${timeout.inMilliseconds}ms';
}

/// The connection failed or dropped: DNS, refused, reset, closed mid-body.
final class HttpNetworkFailure extends HttpFailure {
  final Object cause;

  const HttpNetworkFailure(super.url, this.cause, super.attempts);

  @override
  String get message => '$cause';
}

/// The body passed the caller's `maxBytes` cap and was abandoned mid-read.
/// Never retried — the payload is that size every time.
final class HttpTooLargeFailure extends HttpFailure {
  final int maxBytes;

  const HttpTooLargeFailure(super.url, this.maxBytes, super.attempts);

  @override
  String get message => 'body exceeded $maxBytes bytes';
}

/// The body arrived but was not the shape the caller asked for: invalid JSON
/// (a captive portal or an HTML error page behind a 200), or a field whose type
/// changed under a `fromJson`. Never retried — the same bytes parse the same
/// way every time.
final class HttpDecodeFailure extends HttpFailure {
  final Object cause;

  const HttpDecodeFailure(super.url, this.cause, super.attempts);

  @override
  String get message => 'could not decode the response: $cause';
}

/// A non-2xx answer, raised only when the caller passed `expectOk: true`.
/// Without it a status comes back as data, which is what almost every
/// existing call site already checks for itself.
final class HttpStatusFailure extends HttpFailure {
  final HttpResponse response;

  const HttpStatusFailure(super.url, this.response, super.attempts);

  int get statusCode => response.statusCode;

  @override
  String get message => 'HTTP ${response.statusCode}';
}
