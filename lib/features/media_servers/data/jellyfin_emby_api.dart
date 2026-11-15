import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../models/media_server.dart';
import '../../../models/media_server_library.dart';
import '../../../models/media_server_watch_state.dart';
import 'jellyfin_emby_lookup.dart';
import 'jellyfin_emby_request.dart';
import 'media_server_api.dart';
import 'media_server_http.dart';
import 'media_server_lookup_pager.dart';

/// Shared Jellyfin/Emby user API (moved from the original
/// `MediaServerClient`). Only same-server endpoints are constructed; remote
/// paths supplied in library metadata are never opened directly.
class JellyfinEmbyApi implements MediaServerApi {
  JellyfinEmbyApi(
    http.Client client, {
    required Duration timeout,
    required Duration lookupBudget,
    required DateTime Function() lookupClock,
  }) : this._(
         JellyfinEmbyRequest(MediaServerHttp(client, timeout: timeout)),
         MediaServerLookupPager(timeout: timeout, clock: lookupClock),
         lookupBudget,
         lookupClock,
       );

  JellyfinEmbyApi._(
    this._request,
    MediaServerLookupPager pager,
    Duration lookupBudget,
    DateTime Function() lookupClock,
  ) : _lookup = JellyfinEmbyLookup(
        _request,
        pager,
        lookupBudget: lookupBudget,
        lookupClock: lookupClock,
      );

  final JellyfinEmbyRequest _request;
  final JellyfinEmbyLookup _lookup;

  Future<MediaServerAccount> login({
    required MediaServerKind kind,
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
    Future<void> Function()? authorize,
  }) async {
    final base = MediaServerHttp.normalizeBaseUrl(baseUrl).toString();
    final data = await _request.call(
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
      userId: JellyfinEmbyRequest.segment(user['Id'] as String),
      token: token,
      serverId: serverId,
      deviceId: deviceId,
    );
  }

  @override
  Future<MediaServerAccount> resolve(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
    Object? cacheScope,
    DateTime? deadline,
  }) async => account;

  @override
  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  }) async {
    final info = await _request.call(
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
    final user = await _request.call(
      account.baseUrl,
      'Users/${JellyfinEmbyRequest.segment(account.userId)}',
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

  /// Exact provider IDs only; see [JellyfinEmbyLookup.findItems].
  @override
  Future<List<Map<String, dynamic>>> findItems(
    MediaServerAccount account, {
    required String id,
    required bool isMovie,
    int? season,
    int? episode,
    Future<void> Function()? authorize,
    Object? cacheScope,
    void Function()? onIncomplete,
  }) => _lookup.findItems(
    account,
    id: id,
    isMovie: isMovie,
    season: season,
    episode: episode,
    authorize: authorize,
    cacheScope: cacheScope,
    onIncomplete: onIncomplete,
  );

  @override
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
    final data = await _request.call(
      account.baseUrl,
      views
          ? 'Users/${JellyfinEmbyRequest.segment(account.userId)}/Views'
          : 'Users/${JellyfinEmbyRequest.segment(account.userId)}/Items',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      query: {
        'UserId': account.userId,
        if (views) 'IncludeExternalContent': 'false',
        if (!views) ...{
          if (parentId != null)
            'ParentId': JellyfinEmbyRequest.segment(parentId),
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

  @override
  Future<MediaServerLibraryItem> libraryItem(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final data = await _request.call(
      account.baseUrl,
      'Users/${JellyfinEmbyRequest.segment(account.userId)}/Items/${JellyfinEmbyRequest.segment(itemId)}',
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

  @override
  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _request.image(account, itemId, authorize: authorize);

  @override
  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final data = await _request.call(
      account.baseUrl,
      'Items/${JellyfinEmbyRequest.segment(itemId)}/PlaybackInfo',
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

  @override
  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final item = await _request.call(
      account.baseUrl,
      'Users/${JellyfinEmbyRequest.segment(account.userId)}/Items/${JellyfinEmbyRequest.segment(itemId)}',
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

  @override
  Future<String?> watchSessionId(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final info = await _request.call(
      account.baseUrl,
      'Items/${JellyfinEmbyRequest.segment(itemId)}/PlaybackInfo',
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
    return id is String && id.isNotEmpty
        ? JellyfinEmbyRequest.segment(id)
        : null;
  }

  @override
  Future<void> reportWatchProgress(
    MediaServerAccount account, {
    required String itemId,
    required String mediaSourceId,
    required String playSessionId,
    required String action,
    required int positionMs,
    required bool paused,
    int? durationMs,
    Future<void> Function()? authorize,
  }) async {
    final path = switch (action) {
      'start' => 'Sessions/Playing',
      'progress' => 'Sessions/Playing/Progress',
      'stop' => 'Sessions/Playing/Stopped',
      _ => throw ArgumentError.value(action, 'action'),
    };
    await _request.call(
      account.baseUrl,
      path,
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      body: {
        'ItemId': JellyfinEmbyRequest.segment(itemId),
        'MediaSourceId': JellyfinEmbyRequest.segment(mediaSourceId),
        'PlaySessionId': JellyfinEmbyRequest.segment(playSessionId),
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

  @override
  Future<void> markWatched(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    await _request.call(
      account.baseUrl,
      'Users/${JellyfinEmbyRequest.segment(account.userId)}/PlayedItems/${JellyfinEmbyRequest.segment(itemId)}',
      deviceId: account.deviceId,
      kind: account.kind,
      token: account.token,
      body: const {},
      authorize: authorize,
      allowEmptyResponse: true,
    );
  }
}
