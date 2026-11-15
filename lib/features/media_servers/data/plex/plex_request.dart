import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../../../models/media_server.dart';
import '../../models/media_server_errors.dart';
import '../media_server_http.dart';

/// Plex Media Server headers and request wrapper.
class PlexRequest {
  PlexRequest(this._http, {this.onUnreachable});

  final MediaServerHttp _http;

  /// Told when [account]'s current address stopped answering, so the next
  /// call looks for another one.
  final void Function(MediaServerAccount account)? onUnreachable;

  Duration get timeout => _http.timeout;

  static const product = 'Debrify';
  static const version = '1.0';

  static final _token = RegExp(r'^[A-Za-z0-9._~+/=-]{8,512}$');
  static final _client = RegExp(r'^[A-Za-z0-9_-]{8,128}$');

  /// Client headers for API calls and the player. The token travels only in
  /// `X-Plex-Token`, never in a URL.
  static Map<String, String> headers(
    String clientId, [
    String? token,
    String? sessionId,
  ]) {
    if (!_client.hasMatch(clientId)) {
      throw const MediaServerException(
        'This connection is invalid. Reconnect this server.',
      );
    }
    if (token != null && !_token.hasMatch(token)) {
      throw const MediaServerException(
        'The server returned an invalid session token. Reconnect this server.',
      );
    }
    if (sessionId != null && !_client.hasMatch(sessionId)) {
      throw const MediaServerException('Server playback session unavailable.');
    }
    return {
      'Accept': 'application/json',
      'X-Plex-Product': product,
      'X-Plex-Version': version,
      'X-Plex-Client-Identifier': clientId,
      'X-Plex-Platform': 'Debrify',
      'X-Plex-Device-Name': 'Debrify',
      if (token != null) 'X-Plex-Token': token,
      if (sessionId != null) 'X-Plex-Session-Identifier': sessionId,
    };
  }

  /// One authenticated request against [account]'s current address.
  Future<Map<String, dynamic>> call(
    MediaServerAccount account,
    String path, {
    Map<String, String>? query,
    required String operation,
    String? sessionId,
    Future<void> Function()? authorize,
    Duration? requestTimeout,
    bool allowEmptyResponse = false,
  }) async {
    try {
      return await _http.json(
        () => MediaServerHttp.endpoint(account.baseUrl, path, query),
        headers: () => headers(account.deviceId, account.token, sessionId),
        kind: MediaServerKind.plex,
        operation: operation,
        authorize: authorize,
        requestTimeout: requestTimeout,
        allowEmptyResponse: allowEmptyResponse,
      );
    } on MediaServerUnreachable {
      onUnreachable?.call(account);
      rethrow;
    } on MediaServerTimeout {
      // A request cut short by a lookup budget says nothing about the
      // address; only a full-length timeout does.
      if (requestTimeout == null || requestTimeout >= _http.timeout) {
        onUnreachable?.call(account);
      }
      rethrow;
    } on MediaServerException {
      rethrow;
    } on IOException {
      // package:http wraps only some socket errors; TLS handshake failures
      // arrive raw. Anything else (an authorization callback's own error)
      // keeps its type.
      onUnreachable?.call(account);
      throw const MediaServerUnreachable(
        'Cannot reach the server. Check its address and network connection.',
      );
    }
  }

  /// Bounded thumbnail bytes for [path] on [account]'s current address.
  Future<Uint8List?> image(
    MediaServerAccount account,
    String path,
    Map<String, String> query, {
    Future<void> Function()? authorize,
  }) => _http.image(
    () => MediaServerHttp.endpoint(account.baseUrl, path, query),
    headers: () => headers(account.deviceId, account.token),
    authorize: authorize,
  );
}
