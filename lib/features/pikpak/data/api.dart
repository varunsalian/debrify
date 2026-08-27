import 'dart:convert';

import '../../../core/http/gateway.dart';
import '../models/client_identity.dart';
import 'session.dart';

/// Authenticated PikPak requests: headers, one refresh-and-retry, and PikPak's
/// own error payload turned into a [PikPakApiFailure].
///
/// Replaces a 175-line method that spelled the same request out three times —
/// once to send it, once after a 401, once after an `error_code` 16 — and
/// applied no timeout to any of the three.
///
/// PikPak fingerprints its web client, so [identity] is sent on every call and
/// deliberately overrides whatever default the gateway carries — sending
/// Debrify's own User-Agent here gets the request rejected. It is the same
/// value the auth calls use, which is the point: the identity has to be
/// identical on every path or PikPak notices.
class PikPakApi {
  final HttpGateway _http;
  final PikPakSession _session;
  final PikPakClientIdentity _identity;
  final Duration _timeout;

  PikPakApi({
    required HttpGateway http,
    required PikPakSession session,
    required PikPakClientIdentity identity,
    Duration timeout = const Duration(seconds: 20),
  }) : _http = http,
       _session = session,
       _identity = identity,
       _timeout = timeout;

  /// One authenticated call, returning PikPak's JSON object.
  ///
  /// A rejection that means "your token is stale" is retried exactly once,
  /// after [PikPakSession.refresh]. A second rejection is the answer.
  Future<Map<String, dynamic>> send(
    HttpMethod method,
    Uri url, {
    Map<String, dynamic>? body,
  }) async {
    var response = await _attempt(method, url, body);

    if (_isStaleToken(response)) {
      // refreshAccessToken() owns the logout decision: it returns false for
      // recoverable reasons too (re-auth cooldown, network, profile scope), and
      // clearing the session on those wipes the user's stored PikPak config.
      if (!await _session.refresh()) {
        throw const PikPakSessionExpired();
      }
      response = await _attempt(method, url, body);
    }

    return _result(response);
  }

  Future<_Answer> _attempt(
    HttpMethod method,
    Uri url,
    Map<String, dynamic>? body,
  ) async {
    final token = await _session.accessToken();
    if (token == null || token.isEmpty) {
      throw const PikPakSessionExpired(
        'Not authenticated. Please login first.',
      );
    }

    final headers = _identity.headers(
      accessToken: token,
      deviceId: await _session.deviceId(),
      captchaToken: await _session.captchaToken(),
    );

    // The raw path, not send(): a typed call throws on a non-2xx, and a 4xx
    // body is the ONLY place PikPak ever puts error_code. The status and the
    // payload have to arrive together here.
    final payload = body == null ? null : jsonEncode(body);
    final jsonHeaders = body == null
        ? headers
        : {...headers, 'content-type': 'application/json'};

    final response = await switch (method) {
      HttpMethod.get => _http.get(url, headers: headers, timeout: _timeout),
      HttpMethod.post => _http.post(
        url,
        body: payload,
        headers: jsonHeaders,
        timeout: _timeout,
      ),
      HttpMethod.put => _http.put(
        url,
        body: payload,
        headers: jsonHeaders,
        timeout: _timeout,
      ),
      HttpMethod.patch => _http.patch(
        url,
        body: payload,
        headers: jsonHeaders,
        timeout: _timeout,
      ),
      HttpMethod.delete => _http.delete(
        url,
        body: payload,
        headers: jsonHeaders,
        timeout: _timeout,
      ),
    };

    if (response.bodyBytes.isEmpty) return _Answer(response.statusCode, null);
    try {
      return _Answer(
        response.statusCode,
        await _http.decodeJson(response.body),
      );
    } on FormatException {
      throw PikPakUnexpectedResponse(
        'PikPak returned a non-JSON response.',
        statusCode: response.statusCode,
      );
    }
  }

  /// The shapes PikPak uses to say the access token is stale. PikPak sends
  /// `error_code` 16 under a 200, so status alone does not settle it.
  bool _isStaleToken(_Answer answer) {
    if (answer.statusCode == 401) return true;
    final payload = answer.payload;
    if (payload is! Map) return false;
    final code = payload['error_code'];
    if (code == 16 || code == '16') return true;
    if (payload['error'] == 'unauthenticated') return true;
    // Loose enough to match a legitimate success body, and the retry re-sends
    // the request — which is not safe for addOfflineDownload or batchDelete.
    // Only trust it on a rejection.
    if (answer.statusCode >= 200 && answer.statusCode < 300) return false;
    final description = '${payload['error_description'] ?? ''}'.toLowerCase();
    return description.contains('access token');
  }

  Future<Map<String, dynamic>> _result(_Answer answer) async {
    final payload = answer.payload;

    if (answer.statusCode == 429) throw const PikPakRateLimited();

    if (answer.statusCode >= 200 && answer.statusCode < 300) {
      return _asMap(payload, answer.statusCode);
    }

    final map = payload is Map ? payload : const {};
    final code = map['error_code'];

    if (code == 4002 || code == '4002') {
      await _session.invalidateCaptcha();
    }

    final message = '${map['error_description'] ?? map['error'] ?? ''}';
    throw PikPakRequestFailed(
      message.isNotEmpty ? message : 'PikPak rejected the request.',
      code: code,
      statusCode: answer.statusCode,
    );
  }

  Map<String, dynamic> _asMap(Object? payload, int statusCode) {
    if (payload is Map<String, dynamic>) return payload;
    if (payload is Map) return Map<String, dynamic>.from(payload);
    if (payload == null) {
      // 204/205 carry no body by definition. An empty body under any other
      // status is a truncated response, not an empty object — reading it as
      // one shows an empty folder where there was an error.
      if (statusCode == 204 || statusCode == 205) return const {};
      throw PikPakUnexpectedResponse(
        'PikPak returned an empty response.',
        statusCode: statusCode,
      );
    }
    throw PikPakUnexpectedResponse(
      'PikPak returned an unexpected response shape.',
      statusCode: statusCode,
    );
  }
}

/// Carries the decoded body next to the status, because PikPak's failures are
/// in the body and the gateway's typed path would have thrown before we saw it.
class _Answer {
  final int statusCode;
  final Object? payload;

  const _Answer(this.statusCode, this.payload);
}
