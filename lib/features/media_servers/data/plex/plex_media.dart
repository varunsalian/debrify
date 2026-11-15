import '../../../../models/media_server.dart';
import '../../../../models/media_server_watch_state.dart';
import '../media_server_http.dart';
import 'plex_item_mapping.dart';
import 'plex_request.dart';

/// Plex playback files, connection test and watch state. Watch endpoints
/// start with `:/`, so their paths are written `./:/…` to stay relative to
/// the server address.
class PlexMedia {
  PlexMedia(this._request);

  final PlexRequest _request;

  static const _library = 'com.plexapp.plugins.library';

  static String _itemId(String value) =>
      plexNumericId(value) ??
      (throw const MediaServerException(
        'The server returned an invalid item identifier.',
      ));

  /// The original file of [sourceId] on [account]'s (resolved) address.
  static Uri playbackUrl(
    MediaServerAccount account,
    String itemId,
    String sourceId,
  ) {
    _itemId(itemId);
    final part = plexPartFromSourceId(sourceId);
    if (part == null) {
      throw const MediaServerException(
        'The server returned an invalid item identifier.',
      );
    }
    final name = part.container == 'file' ? 'file' : 'file.${part.container}';
    return MediaServerHttp.endpoint(
      account.baseUrl,
      'library/parts/${part.partId}/$name',
    );
  }

  /// The server must still be the one signed in to, and the token must still
  /// be accepted (identity alone needs no token).
  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  }) async {
    final identity = await _request.call(
      account,
      'identity',
      operation: 'identity',
      authorize: authorize,
    );
    if ((identity['MediaContainer'] as Map?)?['machineIdentifier'] !=
        account.serverId) {
      throw const MediaServerException(
        'The server identity changed. Reconnect this server.',
      );
    }
    await _request.call(
      account,
      'library/sections',
      operation: 'sections',
      authorize: authorize,
    );
  }

  /// One item's metadata, checked to be the item asked for.
  Future<Map<String, dynamic>> metadata(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
    bool checkFiles = false,
  }) async {
    final data = await _request.call(
      account,
      'library/metadata/${_itemId(itemId)}',
      query: checkFiles ? const {'checkFiles': '1'} : null,
      operation: checkFiles ? 'playback_info' : 'api',
      authorize: authorize,
    );
    final rows = (data['MediaContainer'] as Map?)?['Metadata'];
    final item = rows is List && rows.isNotEmpty ? rows.first : null;
    if (item is! Map<String, dynamic> ||
        plexNumericId(item['ratingKey']) != itemId) {
      throw const MediaServerException('The server returned a different item.');
    }
    return item;
  }

  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final item = await metadata(
      account,
      itemId,
      authorize: authorize,
      checkFiles: true,
    );
    if (!const {'movie', 'episode', 'clip'}.contains(item['type'])) {
      return const [];
    }
    return [
      for (final media in item['Media'] as List? ?? const [])
        if (media is Map<String, dynamic>) ?plexMediaSource(media),
    ];
  }

  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    final item = plexItem(
      await metadata(account, itemId, authorize: authorize),
    );
    if (item == null) {
      throw const MediaServerException('The server returned a different item.');
    }
    return MediaServerWatchState.fromItem(item);
  }

  /// Plex stores a position only when the report carries the duration, so a
  /// report without one is not sent.
  Future<void> reportWatchProgress(
    MediaServerAccount account, {
    required String itemId,
    required String playSessionId,
    required String action,
    required int positionMs,
    required bool paused,
    int? durationMs,
    Future<void> Function()? authorize,
  }) async {
    final state = switch (action) {
      'start' || 'progress' => paused ? 'paused' : 'playing',
      'stop' => 'stopped',
      _ => throw ArgumentError.value(action, 'action'),
    };
    final id = _itemId(itemId);
    if (durationMs == null || durationMs <= 0) return;
    await _request.call(
      account,
      './:/timeline',
      query: {
        'ratingKey': id,
        'key': '/library/metadata/$id',
        'identifier': _library,
        'state': state,
        'time': '${positionMs.clamp(0, durationMs)}',
        'duration': '$durationMs',
      },
      sessionId: playSessionId,
      operation: 'watch_report',
      authorize: authorize,
      allowEmptyResponse: true,
    );
  }

  Future<void> markWatched(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    await _request.call(
      account,
      './:/scrobble',
      query: {'key': _itemId(itemId), 'identifier': _library},
      operation: 'watch_report',
      authorize: authorize,
      allowEmptyResponse: true,
    );
  }
}
