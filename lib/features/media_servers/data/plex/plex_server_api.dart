import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../models/media_server.dart';
import '../../../../models/media_server_library.dart';
import '../../../../models/media_server_watch_state.dart';
import '../media_server_api.dart';
import '../media_server_http.dart';
import '../media_server_lookup_pager.dart';
import 'plex_connection_resolver.dart';
import 'plex_library.dart';
import 'plex_lookup.dart';
import 'plex_media.dart';
import 'plex_request.dart';

/// Plex Media Server operations. Callers resolve the account first and use
/// the resolved account for every later call, playback URL and report.
class PlexServerApi implements MediaServerApi {
  PlexServerApi(
    http.Client client, {
    required Duration timeout,
    required Duration lookupBudget,
    required DateTime Function() lookupClock,
  }) : this._(
         MediaServerHttp(client, timeout: timeout),
         lookupBudget,
         lookupClock,
       );

  PlexServerApi._(
    MediaServerHttp http,
    Duration lookupBudget,
    DateTime Function() clock,
  ) : this._parts(
        PlexRequest(http, onUnreachable: PlexConnectionResolver.forget),
        http,
        lookupBudget,
        clock,
      );

  PlexServerApi._parts(
    PlexRequest request,
    MediaServerHttp http,
    Duration lookupBudget,
    DateTime Function() clock,
  ) : this._wired(request, PlexMedia(request), http, lookupBudget, clock);

  PlexServerApi._wired(
    PlexRequest request,
    this._media,
    MediaServerHttp http,
    Duration lookupBudget,
    DateTime Function() clock,
  ) : _resolver = PlexConnectionResolver(http, clock: clock),
      _lookup = PlexLookup(
        request,
        MediaServerLookupPager(timeout: http.timeout, clock: clock),
        lookupBudget: lookupBudget,
        clock: clock,
      ),
      _library = PlexLibrary(request, _media);

  final PlexConnectionResolver _resolver;
  final PlexMedia _media;
  final PlexLookup _lookup;
  final PlexLibrary _library;

  static Map<String, String> headers(String clientId, [String? token]) =>
      PlexRequest.headers(clientId, token);

  static Uri playbackUrl(
    MediaServerAccount account,
    String itemId,
    String sourceId,
  ) => PlexMedia.playbackUrl(account, itemId, sourceId);

  @override
  Future<MediaServerAccount> resolve(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
    Object? cacheScope,
    DateTime? deadline,
  }) => _resolver.resolve(
    account,
    authorize: authorize,
    cacheScope: cacheScope,
    deadline: deadline,
  );

  @override
  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  }) async => _media.testConnection(
    await resolve(account, authorize: authorize),
    authorize: authorize,
  );

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
  }) => _library.library(
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
  }) => _library.libraryItem(account, itemId, authorize: authorize);

  @override
  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _library.libraryImage(account, itemId, authorize: authorize);

  @override
  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _media.mediaSources(account, itemId, authorize: authorize);

  @override
  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) => _media.watchState(account, itemId, authorize: authorize);

  /// Plex has no server-issued session; the caller generates one and it is
  /// sent as `X-Plex-Session-Identifier`.
  @override
  Future<String?> watchSessionId(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  }) async {
    await authorize?.call();
    return null;
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
  }) => _media.reportWatchProgress(
    account,
    itemId: itemId,
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
  }) => _media.markWatched(account, itemId, authorize: authorize);
}
