import 'dart:typed_data';

import '../../../models/media_server.dart';
import 'media_server_http.dart';

/// Jellyfin/Emby headers, identifiers and request wrapper (moved from the
/// original `MediaServerClient`).
class JellyfinEmbyRequest {
  JellyfinEmbyRequest(this._http);

  final MediaServerHttp _http;

  static String segment(String value) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
      throw const MediaServerException(
        'The server returned an invalid item identifier.',
      );
    }
    return value;
  }

  static Map<String, String> headers(
    String deviceId, [
    String? token,
    MediaServerKind kind = MediaServerKind.jellyfin,
  ]) {
    // Jellyfin 12 no longer accepts X-Emby-Token. Include the session token in
    // the standard authorization value for API calls AND player requests;
    // keep the legacy header for older Jellyfin/Emby installations.
    // Tokens occupy a quoted parameter, so reject delimiters/control bytes
    // rather than allowing a server response to inject authorization fields.
    if (token != null && !RegExp(r'^[a-zA-Z0-9._~+/-]+=*$').hasMatch(token)) {
      throw const MediaServerException(
        'The server returned an invalid session token. Reconnect this server.',
      );
    }
    final parameters = [
      'Client="Debrify"',
      'Device="Debrify"',
      'DeviceId="${segment(deviceId)}"',
      'Version="1.0"',
      if (token != null) 'Token="$token"',
    ].join(', ');
    return {
      'Authorization':
          '${kind == MediaServerKind.emby ? 'Emby' : 'MediaBrowser'} $parameters',
      if (token != null) 'X-Emby-Token': token,
      'Accept': 'application/json',
    };
  }

  static Uri playbackUrl(
    MediaServerAccount account,
    String itemId,
    String sourceId,
  ) => MediaServerHttp.endpoint(
    account.baseUrl,
    'Videos/${segment(itemId)}/stream',
    {'Static': 'true', 'MediaSourceId': sourceId, 'DeviceId': account.deviceId},
  );

  Future<Map<String, dynamic>> call(
    String baseUrl,
    String path, {
    required String deviceId,
    MediaServerKind kind = MediaServerKind.jellyfin,
    String? token,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Future<void> Function()? authorize,
    bool allowEmptyResponse = false,
    Duration? requestTimeout,
  }) => _http.json(
    () => MediaServerHttp.endpoint(baseUrl, path, query),
    headers: () => headers(deviceId, token, kind),
    kind: kind,
    operation: path.endsWith('/PlaybackInfo')
        ? 'playback_info'
        : path.contains('Sessions/')
        ? 'watch_report'
        : 'api',
    method: body == null ? 'GET' : 'POST',
    body: body,
    authorize: authorize,
    allowEmptyResponse: allowEmptyResponse,
    requestTimeout: requestTimeout,
  );

  /// Authenticated, bounded thumbnails. Never forward credentials on redirects.
  Future<Uint8List?> image(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _http.image(
    () => MediaServerHttp.endpoint(
      account.baseUrl,
      'Items/${segment(itemId)}/Images/Primary',
      {'MaxWidth': '360', 'Quality': '85'},
    ),
    headers: () => headers(account.deviceId, account.token, account.kind),
    authorize: authorize,
  );
}
