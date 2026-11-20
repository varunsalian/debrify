import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/models/ledger_media.dart';

/// A pending device sign-in: the user enters [userCode] at [verificationUri]
/// while the app polls with [deviceCode].
class LedgerDeviceCode {
  const LedgerDeviceCode({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.verificationUriComplete,
    required this.expiresIn,
    required this.interval,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final String verificationUriComplete;
  final Duration expiresIn;
  final Duration interval;
}

/// An access/refresh token pair. Access tokens last about an hour and the
/// refresh token rotates on every exchange, so both are always stored as one.
class LedgerTokens {
  const LedgerTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  int get expiryMs => expiresAt.millisecondsSinceEpoch;
}

enum LedgerPollStatus {
  approved,
  pending,
  slowDown,
  denied,
  expired,
  networkError,
  error,
}

class LedgerPollResult {
  const LedgerPollResult(this.status, [this.tokens]);

  final LedgerPollStatus status;
  final LedgerTokens? tokens;
}

/// Outcome of a refresh-token exchange. [rejected] means the server refused
/// the refresh token itself (revoked/expired), so retrying cannot help.
class LedgerRefreshResult {
  const LedgerRefreshResult._(this.tokens, {this.rejected = false});

  const LedgerRefreshResult.success(LedgerTokens tokens) : this._(tokens);
  const LedgerRefreshResult.rejected() : this._(null, rejected: true);
  const LedgerRefreshResult.failed() : this._(null);

  final LedgerTokens? tokens;
  final bool rejected;
}

/// The unauthenticated OAuth endpoints (RFC 8628 device flow + refresh).
class LedgerAuthApi {
  LedgerAuthApi({
    http.Client? client,
    this.baseUrl = kLedgerApiBaseUrl,
    DateTime Function()? now,
  }) : _client = client,
       _now = now ?? DateTime.now;

  final http.Client? _client;
  final String baseUrl;
  final DateTime Function() _now;

  static const Duration _timeout = Duration(seconds: 15);

  Future<http.Response> _postForm(String path, Map<String, String> body) {
    final uri = Uri.parse('$baseUrl$path');
    final client = _client;
    final request = client == null
        ? http.post(uri, body: body)
        : client.post(uri, body: body);
    return request.timeout(_timeout);
  }

  /// Starts a device sign-in. Returns null on any failure.
  Future<LedgerDeviceCode?> startDeviceAuthorization() async {
    try {
      final response = await _postForm('/oauth/device_authorization', {
        'client_id': kLedgerClientId,
      });
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final deviceCode = ledgerString(json['device_code']);
      final userCode = ledgerString(json['user_code']);
      final uri = ledgerString(json['verification_uri']);
      if (deviceCode == null || userCode == null || uri == null) return null;
      final interval = ledgerPositiveInt(json['interval']) ?? 5;
      final expiresIn = ledgerPositiveInt(json['expires_in']) ?? 600;
      return LedgerDeviceCode(
        deviceCode: deviceCode,
        userCode: userCode,
        verificationUri: uri,
        verificationUriComplete:
            ledgerString(json['verification_uri_complete']) ?? uri,
        expiresIn: Duration(seconds: expiresIn.clamp(1, 3600)),
        interval: Duration(seconds: interval.clamp(1, 60)),
      );
    } catch (_) {
      return null;
    }
  }

  /// One poll of the device-code grant.
  Future<LedgerPollResult> pollDeviceToken(String deviceCode) async {
    final http.Response response;
    try {
      response = await _postForm('/oauth/token', {
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        'device_code': deviceCode,
        'client_id': kLedgerClientId,
      });
    } catch (_) {
      return const LedgerPollResult(LedgerPollStatus.networkError);
    }
    if (response.statusCode == 200) {
      final tokens = _parseTokens(response.body);
      return tokens == null
          ? const LedgerPollResult(LedgerPollStatus.error)
          : LedgerPollResult(LedgerPollStatus.approved, tokens);
    }
    if (response.statusCode >= 500) {
      return const LedgerPollResult(LedgerPollStatus.networkError);
    }
    return LedgerPollResult(switch (_oauthError(response.body)) {
      'authorization_pending' => LedgerPollStatus.pending,
      'slow_down' => LedgerPollStatus.slowDown,
      'access_denied' => LedgerPollStatus.denied,
      'expired_token' => LedgerPollStatus.expired,
      _ => LedgerPollStatus.error,
    });
  }

  Future<LedgerRefreshResult> refresh(String refreshToken) async {
    final http.Response response;
    try {
      response = await _postForm('/oauth/token', {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': kLedgerClientId,
      });
    } catch (_) {
      return const LedgerRefreshResult.failed();
    }
    if (response.statusCode == 200) {
      final tokens = _parseTokens(response.body);
      return tokens == null
          ? const LedgerRefreshResult.failed()
          : LedgerRefreshResult.success(tokens);
    }
    if (response.statusCode >= 400 && response.statusCode < 500) {
      final error = _oauthError(response.body);
      if (error == 'invalid_grant' || response.statusCode == 401) {
        return const LedgerRefreshResult.rejected();
      }
    }
    return const LedgerRefreshResult.failed();
  }

  /// Best-effort server sign-out of this session.
  Future<void> revoke(String refreshToken) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/sessions:revoke');
      final body = jsonEncode({'refreshToken': refreshToken});
      const headers = {'Content-Type': 'application/json'};
      final client = _client;
      await (client == null
              ? http.post(uri, headers: headers, body: body)
              : client.post(uri, headers: headers, body: body))
          .timeout(_timeout);
    } catch (_) {
      // Local sign-out already happened; the session expires on its own.
    }
  }

  LedgerTokens? _parseTokens(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final access = ledgerString(json['access_token']);
      final refresh = ledgerString(json['refresh_token']);
      final expiresIn = ledgerPositiveInt(json['expires_in']);
      if (access == null || refresh == null || expiresIn == null) return null;
      return LedgerTokens(
        accessToken: access,
        refreshToken: refresh,
        expiresAt: _now().add(Duration(seconds: expiresIn)),
      );
    } catch (_) {
      return null;
    }
  }

  String? _oauthError(String body) {
    try {
      final json = jsonDecode(body);
      return json is Map ? ledgerString(json['error']) : null;
    } catch (_) {
      return null;
    }
  }
}
