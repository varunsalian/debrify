import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../features/media_servers/data/jellyfin_emby_api.dart';
import '../features/media_servers/data/jellyfin_emby_request.dart';
import '../features/media_servers/data/media_server_api.dart';
import '../features/media_servers/data/media_server_http.dart';
import '../features/media_servers/data/plex/plex_server_api.dart';
import '../models/media_server.dart';
import '../models/media_server_library.dart';
import '../models/media_server_watch_state.dart';

/// Media-server entry point used by search, library browsing and watch sync.
/// It wires the Jellyfin/Emby and Plex implementations on one HTTP client
/// and routes each call by the account's kind.
class MediaServerClient implements MediaServerApi {
  MediaServerClient({
    http.Client? client,
    Duration timeout = const Duration(seconds: 12),
    Duration lookupBudget = const Duration(seconds: 12),
    DateTime Function()? lookupClock,
  }) : this._(
         client ?? http.Client(),
         timeout,
         lookupBudget,
         lookupClock ?? DateTime.now,
       );

  MediaServerClient._(
    this._client,
    this.timeout,
    this.lookupBudget,
    DateTime Function() clock,
  ) : _jellyfin = JellyfinEmbyApi(
        _client,
        timeout: timeout,
        lookupBudget: lookupBudget,
        lookupClock: clock,
      ),
      _plex = PlexServerApi(
        _client,
        timeout: timeout,
        lookupBudget: lookupBudget,
        lookupClock: clock,
      );

  final http.Client _client;
  final Duration timeout;
  final Duration lookupBudget;
  final JellyfinEmbyApi _jellyfin;
  final PlexServerApi _plex;

  void close() => _client.close();

  MediaServerApi _for(MediaServerAccount account) =>
      account.kind == MediaServerKind.plex ? _plex : _jellyfin;

  /// Whether [id] is one the servers can match exactly (`tt…`, `tmdb:N`,
  /// `tvdb:N`); anything else never needs a server request.
  static bool canMatch(String id) =>
      RegExp(r'^(?:tt\d+|tmdb:\d+|tvdb:\d+)$').hasMatch(id);

  static Uri normalizeBaseUrl(String value) =>
      MediaServerHttp.normalizeBaseUrl(value);

  static Uri endpoint(
    String baseUrl,
    String path, [
    Map<String, String>? query,
  ]) => MediaServerHttp.endpoint(baseUrl, path, query);

  /// Headers for API calls and the player. Plex sends the token only as
  /// `X-Plex-Token`.
  static Map<String, String> headers(
    String deviceId, [
    String? token,
    MediaServerKind kind = MediaServerKind.jellyfin,
  ]) => kind == MediaServerKind.plex
      ? PlexServerApi.headers(deviceId, token)
      : JellyfinEmbyRequest.headers(deviceId, token, kind);

  /// The only route to a player URL. Give it the account returned by
  /// [resolve], so a fallback address reaches the player.
  static Uri playbackUrl(
    MediaServerAccount account,
    String itemId,
    String sourceId,
  ) => account.kind == MediaServerKind.plex
      ? PlexServerApi.playbackUrl(account, itemId, sourceId)
      : JellyfinEmbyRequest.playbackUrl(account, itemId, sourceId);

  /// Jellyfin/Emby username sign-in. Plex signs in through plex.tv instead.
  Future<MediaServerAccount> login({
    required MediaServerKind kind,
    required String baseUrl,
    required String username,
    required String password,
    required String deviceId,
    Future<void> Function()? authorize,
  }) {
    if (kind == MediaServerKind.plex) {
      throw ArgumentError.value(kind, 'kind', 'Plex signs in with plex.tv');
    }
    return _jellyfin.login(
      kind: kind,
      baseUrl: baseUrl,
      username: username,
      password: password,
      deviceId: deviceId,
      authorize: authorize,
    );
  }

  @override
  Future<MediaServerAccount> resolve(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
    Object? cacheScope,
    DateTime? deadline,
  }) => _for(account).resolve(
    account,
    authorize: authorize,
    cacheScope: cacheScope,
    deadline: deadline,
  );

  @override
  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  }) => _for(account).testConnection(account, authorize: authorize);

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
  }) => _for(account).findItems(
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
  }) => _for(account).library(
    account,
    parentId: parentId,
    views: views,
    offset: offset,
    search: search,
    sort: sort,
    mode: mode,
    episodeOrder: episodeOrder,
    authorize: authorize,
  );

  @override
  Future<MediaServerLibraryItem> libraryItem(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).libraryItem(account, itemId, authorize: authorize);

  @override
  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).libraryImage(account, itemId, authorize: authorize);

  @override
  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).mediaSources(account, itemId, authorize: authorize);

  @override
  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).watchState(account, itemId, authorize: authorize);

  @override
  Future<String?> watchSessionId(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).watchSessionId(account, itemId, authorize: authorize);

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
  }) => _for(account).reportWatchProgress(
    account,
    itemId: itemId,
    mediaSourceId: mediaSourceId,
    playSessionId: playSessionId,
    action: action,
    positionMs: positionMs,
    paused: paused,
    durationMs: durationMs,
    authorize: authorize,
  );

  @override
  Future<void> markWatched(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _for(account).markWatched(account, itemId, authorize: authorize);
}
