import 'diagnostic_log.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/media_server.dart';
import '../models/media_server_library.dart';
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
      'DeviceId="${_segment(deviceId)}"',
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
      if (allowEmptyResponse && response.bodyBytes.isEmpty) {
        outcome = 'ok';
        return {};
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const FormatException();
      outcome = 'ok';
      return data;
    } on MediaServerException {
      rethrow;
    } on TimeoutException {
      outcome = 'timeout';
      throw const MediaServerException(
        'Server timed out. Check its address and network connection.',
      );
    } on FormatException {
      outcome = 'invalid_response';
      throw const MediaServerException(
        'The server returned an invalid response. Check the server URL.',
      );
    } on http.ClientException {
      outcome = 'network_error';
      throw const MediaServerException(
        'Cannot reach the server. Check its address and network connection.',
      );
    } finally {
      // Never persist paths, query parameters, bodies, headers, or exceptions.
      DiagnosticLog.instance.recordEvent(
        source: 'media_server',
        event: 'request',
        fields: {
          'kind': DiagnosticLabel(kind.name),
          'operation': DiagnosticLabel(
            path.endsWith('/PlaybackInfo')
                ? 'playback_info'
                : path.contains('Sessions/')
                ? 'watch_report'
                : 'api',
          ),
          'status': status,
          'outcome': DiagnosticLabel(outcome),
          'elapsed_ms': timer.elapsedMilliseconds,
        },
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

  // Jellyfin does not implement Emby's AnyProviderIdEquals. Scan lightweight
  // metadata pages and verify IDs locally; never retain the unrelated library.
  Future<List<Map<String, dynamic>>> _jellyfinItems(
    MediaServerAccount account,
    String path,
    Map<String, String> query,
    bool Function(Map<String, dynamic>) matches,
    Future<void> Function()? authorize,
  ) async {
    const pageSize = 500;
    final found = <Map<String, dynamic>>[];
    final pageBoundaries = <String>{};
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var start = 0;
    while (true) {
      if (DateTime.now().isAfter(deadline)) {
        throw const MediaServerException(
          'Server search timed out. Please retry.',
        );
      }
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
          'Limit': '$pageSize',
          'EnableTotalRecordCount': 'true',
        },
        authorize: authorize,
      );
      final page = data['Items'];
      if (page is! List || page.any((item) => item is! Map<String, dynamic>)) {
        throw const MediaServerException(
          'The server returned an invalid library response.',
        );
      }
      if (page.isEmpty) return found;
      // Protect against servers/proxies that ignore StartIndex and repeat pages.
      final boundary = jsonEncode([
        page.first['Id'],
        page.last['Id'],
        page.length,
      ]);
      if (!pageBoundaries.add(boundary)) {
        throw const MediaServerException(
          'The server repeated a library page. Please retry or check the server.',
        );
      }
      found.addAll(page.cast<Map<String, dynamic>>().where(matches));
      start += page.length;
      final total = data['TotalRecordCount'];
      if (total is num ? start >= total : page.length < pageSize) return found;
    }
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
    bool matchesIdentity(Map<String, dynamic> item) {
      final ids = item['ProviderIds'];
      return item['Type'] == (isMovie ? 'Movie' : 'Series') &&
          ids is Map &&
          ids.entries.any(
            (entry) =>
                entry.key.toString().toLowerCase() == provider &&
                entry.value.toString() == providerId,
          );
    }

    final path = 'Users/${_segment(account.userId)}/Items';
    final query = {
      'Recursive': 'true',
      'IncludeItemTypes': isMovie ? 'Movie' : 'Series',
      'EnableImages': 'false',
      'EnableUserData': 'false',
    };
    final exact = account.kind == MediaServerKind.jellyfin
        ? await _jellyfinItems(
            account,
            path,
            {
              ...query,
              'Fields': 'ProviderIds',
              'Has${provider[0].toUpperCase()}${provider.substring(1)}Id':
                  'true',
              'SortBy': 'SortName',
              'SortOrder': 'Ascending',
            },
            matchesIdentity,
            authorize,
          )
        : (await _items(account, path, {
            ...query,
            'AnyProviderIdEquals': '$provider.$providerId',
            'Fields': 'ProviderIds,MediaSources,MediaStreams',
          }, authorize)).where(matchesIdentity).toList();
    if (isMovie) {
      return exact.where((item) => item['IsPlaceHolder'] != true).toList();
    }
    final episodes = <Map<String, dynamic>>[];
    for (final series in exact) {
      final path = 'Shows/${_segment(series['Id'] as String)}/Episodes';
      final query = {
        'Season': '$season',
        // PlaybackInfo supplies streams after matching. Avoid downloading every
        // episode's versions/tracks while scanning a large Jellyfin season.
        if (account.kind == MediaServerKind.emby)
          'Fields': 'MediaSources,MediaStreams',
        'IsMissing': 'false',
        'EnableImages': 'false',
        'EnableUserData': 'false',
      };
      bool matchesEpisode(Map<String, dynamic> item) =>
          item['Type'] == 'Episode' &&
          item['ParentIndexNumber'] == season &&
          item['IndexNumber'] == episode &&
          item['IsMissing'] != true &&
          item['IsPlaceHolder'] != true;
      final found = account.kind == MediaServerKind.jellyfin
          ? await _jellyfinItems(
              account,
              path,
              query,
              matchesEpisode,
              authorize,
            )
          : (await _items(
              account,
              path,
              query,
              authorize,
            )).where(matchesEpisode).toList();
      episodes.addAll(found);
    }
    return episodes;
  }

  Future<MediaServerLibraryPage> library(
    MediaServerAccount account, {
    String? parentId,
    bool views = false,
    int offset = 0,
    String search = '',
    String sort = 'SortName',
    String mode = 'browse',
    bool episodeOrder = false,
    Future<void> Function()? authorize,
  }) async {
    if (offset < 0 ||
        !const {'SortName', 'DateCreated', 'ProductionYear'}.contains(sort) ||
        !const {'browse', 'recent', 'resume'}.contains(mode)) {
      throw ArgumentError('Invalid library query');
    }
    final data = await _request(
      account.baseUrl,
      views
          ? 'Users/${_segment(account.userId)}/Views'
          : 'Users/${_segment(account.userId)}/Items',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      query: {
        'UserId': account.userId,
        if (views) 'IncludeExternalContent': 'false',
        if (!views) ...{
          if (parentId != null) 'ParentId': _segment(parentId),
          'StartIndex': '$offset',
          'Limit': '60',
          'EnableTotalRecordCount': 'true',
          'Recursive': search.trim().isNotEmpty || mode != 'browse'
              ? 'true'
              : 'false',
          if (search.trim().isNotEmpty) 'SearchTerm': search.trim(),
          if (search.trim().isNotEmpty || mode != 'browse')
            'IncludeItemTypes': mode == 'browse'
                ? 'Movie,Series,Episode,Video,MusicVideo'
                : 'Movie,Episode,Video,MusicVideo',
          if (mode == 'resume') 'Filters': 'IsResumable',
          'SortBy': mode == 'resume'
              ? 'DatePlayed,SortName'
              : mode == 'recent'
              ? 'DateCreated,SortName'
              : episodeOrder
              ? 'ParentIndexNumber,IndexNumber,SortName'
              : sort == 'SortName'
              ? 'SortName'
              : '$sort,SortName',
          'SortOrder': mode != 'browse' || (!episodeOrder && sort != 'SortName')
              ? 'Descending'
              : 'Ascending',
          'Fields': 'Overview,PrimaryImageAspectRatio,DateCreated',
          'EnableImages': 'true',
          'ImageTypeLimit': '1',
          'EnableUserData': 'true',
          'IsMissing': 'false',
        },
      },
      authorize: authorize,
    );
    return MediaServerLibraryPage.fromJson(data, offset, 60);
  }

  Future<MediaServerLibraryItem> libraryItem(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final data = await _request(
      account.baseUrl,
      'Users/${_segment(account.userId)}/Items/${_segment(itemId)}',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      authorize: authorize,
    );
    final item = MediaServerLibraryItem.fromJson(data);
    if (item.id != itemId) {
      throw const MediaServerException('The server returned a different item.');
    }
    return item;
  }

  /// Authenticated, bounded thumbnails. Never forward credentials on redirects.
  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    await authorize?.call();
    final request =
        http.Request(
            'GET',
            endpoint(
              account.baseUrl,
              'Items/${_segment(itemId)}/Images/Primary',
              {'MaxWidth': '360', 'Quality': '85'},
            ),
          )
          ..followRedirects = false
          ..headers.addAll(
            headers(account.deviceId, account.token, account.kind),
          );
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
