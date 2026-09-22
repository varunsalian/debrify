import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/media_server.dart';
import '../models/media_server_watch_state.dart';

/// Shared Jellyfin/Emby user API. Only same-server endpoints are constructed;
/// remote paths supplied in library metadata are never opened directly.
class MediaServerClient {
  MediaServerClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  void close() => _client.close();

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

  static String _segment(String value) {
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
  ]) => {
    'Authorization':
        '${kind == MediaServerKind.emby ? 'Emby' : 'MediaBrowser'} Client="Debrify", Device="Debrify", DeviceId="${_segment(deviceId)}", Version="1.0"',
    if (token != null) 'X-Emby-Token': token,
    'Accept': 'application/json',
  };

  Future<Map<String, dynamic>> _request(
    String baseUrl,
    String path, {
    required String deviceId,
    MediaServerKind kind = MediaServerKind.jellyfin,
    String? token,
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Future<void> Function()? authorize,
    bool allowEmptyResponse = false,
  }) async {
    await authorize?.call();
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            endpoint(baseUrl, path, query),
          )
          // Never forward a session token or login body through an HTTP redirect.
          ..followRedirects = false
          ..headers.addAll(headers(deviceId, token, kind));
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async {
        final stream = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in stream.stream) {
          bytes.addAll(chunk);
          if (bytes.length > 8 * 1024 * 1024) {
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
      })().timeout(timeout);
      await authorize?.call();
      if (response.statusCode == 401) {
        throw const MediaServerException(
          'Sign-in expired or credentials are incorrect. Reconnect this server.',
        );
      }
      if (response.statusCode == 403) {
        throw const MediaServerException(
          'This server user does not have permission to play this content.',
        );
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const MediaServerException(
          'The server redirected this request. Use its final URL, including any base path.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MediaServerException(
          'The server could not complete the request (HTTP ${response.statusCode}).',
        );
      }
      if (allowEmptyResponse && response.bodyBytes.isEmpty) return {};
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      return data;
    } on MediaServerException {
      rethrow;
    } on TimeoutException {
      throw const MediaServerException(
        'Server timed out. Check its address and network connection.',
      );
    } on FormatException {
      throw const MediaServerException(
        'The server returned an invalid response. Check the server URL.',
      );
    } on http.ClientException {
      throw const MediaServerException(
        'Cannot reach the server. Check its address and network connection.',
      );
    }
  }

  Future<MediaServerAccount> login({
    required MediaServerKind kind,
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
    Future<void> Function()? authorize,
  }) async {
    final base = normalizeBaseUrl(baseUrl).toString();
    final data = await _request(
      base,
      'Users/AuthenticateByName',
      deviceId: deviceId,
      kind: kind,
      body: {'Username': username.trim(), 'Pw': password},
      authorize: authorize,
    );
    final user = data['User'];
    final token = data['AccessToken'];
    final serverId = data['ServerId'];
    if (user is! Map ||
        user['Id'] is! String ||
        token is! String ||
        token.isEmpty ||
        serverId is! String ||
        serverId.isEmpty) {
      throw const MediaServerException(
        'The server returned an incomplete sign-in response.',
      );
    }
    return MediaServerAccount(
      kind: kind,
      baseUrl: base,
      userId: _segment(user['Id'] as String),
      token: token,
      serverId: serverId,
      deviceId: deviceId,
    );
  }

  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  }) async {
    final info = await _request(
      account.baseUrl,
      'System/Info/Public',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      authorize: authorize,
    );
    if (info['Id'] != account.serverId) {
      throw const MediaServerException(
        'The server identity changed. Reconnect this server.',
      );
    }
    // Public server identity alone cannot validate an expired/revoked token.
    // Reading the signed-in user's own record requires no administrator role.
    final user = await _request(
      account.baseUrl,
      'Users/${_segment(account.userId)}',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      authorize: authorize,
    );
    if (user['Id'] != account.userId) {
      throw const MediaServerException(
        'The server user changed. Reconnect this server.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _items(
    MediaServerAccount account,
    String path,
    Map<String, String> query,
    Future<void> Function()? authorize,
  ) async {
    final items = <Map<String, dynamic>>[];
    // A bounded paginated query, not a full library download. Server-side
    // filters are verified again by the caller before anything is playable.
    for (var start = 0; start < 1000; start += 100) {
      final data = await _request(
        account.baseUrl,
        path,
        deviceId: account.deviceId,
        kind: account.kind,
        token: account.token,
        query: {
          ...query,
          'UserId': account.userId,
          'StartIndex': '$start',
          'Limit': '100',
        },
        authorize: authorize,
      );
      final page = data['Items'];
      if (page is! List) {
        throw const MediaServerException(
          'The server returned an invalid library response.',
        );
      }
      items.addAll(page.whereType<Map<String, dynamic>>());
      final total = data['TotalRecordCount'];
      if (page.length < 100 || (total is num && start + page.length >= total)) {
        return items;
      }
    }
    throw const MediaServerException(
      'The server returned too many matches. Check its metadata IDs.',
    );
  }

  /// Exact provider IDs only. Avoid fuzzy guesses, remakes and alternate
  /// anime numbering: missing metadata should produce no match, not a wrong one.
  Future<List<Map<String, dynamic>>> findItems(
    MediaServerAccount account, {
    required String id,
    required bool isMovie,
    int? season,
    int? episode,
    Future<void> Function()? authorize,
  }) async {
    final provider = RegExp(r'^tt\d+$').hasMatch(id)
        ? 'imdb'
        : RegExp(r'^tmdb:\d+$').hasMatch(id)
        ? 'tmdb'
        : RegExp(r'^tvdb:\d+$').hasMatch(id)
        ? 'tvdb'
        : null;
    if (provider == null || (!isMovie && (season == null || episode == null))) {
      return [];
    }
    final providerId = provider == 'imdb' ? id : id.split(':').last;
    final matches =
        await _items(account, 'Users/${_segment(account.userId)}/Items', {
          'Recursive': 'true',
          'IncludeItemTypes': isMovie ? 'Movie' : 'Series',
          'AnyProviderIdEquals': '$provider.$providerId',
          'Fields': 'ProviderIds,MediaSources,MediaStreams',
          'EnableImages': 'false',
          'EnableUserData': 'false',
        }, authorize);
    final exact = matches.where((item) {
      final ids = item['ProviderIds'];
      return item['Type'] == (isMovie ? 'Movie' : 'Series') &&
          ids is Map &&
          ids.entries.any(
            (entry) =>
                entry.key.toString().toLowerCase() == provider &&
                entry.value.toString() == providerId,
          );
    }).toList();
    if (isMovie) {
      return exact.where((item) => item['IsPlaceHolder'] != true).toList();
    }
    final episodes = <Map<String, dynamic>>[];
    for (final series in exact) {
      final found = await _items(
        account,
        'Shows/${_segment(series['Id'] as String)}/Episodes',
        {
          'Season': '$season',
          'Fields': 'MediaSources,MediaStreams',
          'IsMissing': 'false',
          'EnableImages': 'false',
          'EnableUserData': 'false',
        },
        authorize,
      );
      episodes.addAll(
        found.where(
          (item) =>
              item['Type'] == 'Episode' &&
              item['ParentIndexNumber'] == season &&
              item['IndexNumber'] == episode &&
              item['IsMissing'] != true &&
              item['IsPlaceHolder'] != true,
        ),
      );
    }
    return episodes;
  }

  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final data = await _request(
      account.baseUrl,
      'Items/${_segment(itemId)}/PlaybackInfo',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      query: {'UserId': account.userId},
      authorize: authorize,
    );
    if (data['ErrorCode'] != null) {
      throw const MediaServerException(
        'This item cannot be played by this server user.',
      );
    }
    final sources = data['MediaSources'];
    if (sources is! List) {
      throw const MediaServerException(
        'The server returned no playback information.',
      );
    }
    return sources
        .whereType<Map<String, dynamic>>()
        .where(
          (source) =>
              source['SupportsDirectPlay'] == true &&
              source['RequiresOpening'] != true &&
              source['IsRemote'] != true &&
              source['Protocol']?.toString().toLowerCase() == 'file' &&
              source['Id'] is String &&
              (source['Id'] as String).isNotEmpty,
        )
        .toList();
  }

  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final item = await _request(
      account.baseUrl,
      'Users/${_segment(account.userId)}/Items/${_segment(itemId)}',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      authorize: authorize,
    );
    if (item['Id'] != itemId) {
      throw const MediaServerException('The server returned a different item.');
    }
    return MediaServerWatchState.fromItem(item);
  }

  Future<String?> watchSessionId(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final info = await _request(
      account.baseUrl,
      'Items/${_segment(itemId)}/PlaybackInfo',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      query: {'UserId': account.userId},
      authorize: authorize,
    );
    final id = info['PlaySessionId'];
    if (info['ErrorCode'] != null) {
      throw const MediaServerException('Server playback session unavailable.');
    }
    return id is String && id.isNotEmpty ? _segment(id) : null;
  }

  Future<void> reportWatchProgress(
    MediaServerAccount account, {
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required String action,
    required int positionMs,
    required bool paused,
    Future<void> Function()? authorize,
  }) async {
    final path = switch (action) {
      'start' => 'Sessions/Playing',
      'progress' => 'Sessions/Playing/Progress',
      'stop' => 'Sessions/Playing/Stopped',
      _ => throw ArgumentError.value(action, 'action'),
    };
    await _request(
      account.baseUrl,
      path,
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      body: {
        'ItemId': _segment(itemId),
        'MediaSourceId': _segment(mediaSourceId),
        'PlaySessionId': _segment(playSessionId),
        'PositionTicks': (positionMs < 0 ? 0 : positionMs) * 10000,
        'IsPaused': paused,
        'CanSeek': true,
        'PlayMethod': 'DirectPlay',
        if (action == 'progress') 'EventName': paused ? 'Pause' : 'TimeUpdate',
      },
      authorize: authorize,
      allowEmptyResponse: true,
    );
  }

  Future<void> markWatched(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    await _request(
      account.baseUrl,
      'Users/${_segment(account.userId)}/PlayedItems/${_segment(itemId)}',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      body: const {},
      authorize: authorize,
      allowEmptyResponse: true,
    );
  }

  static Uri playbackUrl(
    MediaServerAccount account,
    String itemId,
    String sourceId,
  ) => endpoint(account.baseUrl, 'Videos/${_segment(itemId)}/stream', {
    'Static': 'true',
    'MediaSourceId': sourceId,
    'DeviceId': account.deviceId,
  });
}
