import 'dart:typed_data';

import '../../../models/media_server.dart';
import '../../../models/media_server_library.dart';
import '../../../models/media_server_watch_state.dart';

/// Server operations used by search, library browsing and watch sync. One
/// implementation per server family; `MediaServerClient` routes each call by
/// the account's kind.
///
/// Items and media sources are maps with the keys documented in
/// `plex/plex_item_mapping.dart` (temporary exception, see
/// docs/media-servers.md).
abstract interface class MediaServerApi {
  /// The account with a reachable, identity-checked [MediaServerAccount.baseUrl].
  /// Every later call, playback URL and watch report must use this account.
  Future<MediaServerAccount> resolve(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
    Object? cacheScope,
    DateTime? deadline,
  });

  Future<void> testConnection(
    MediaServerAccount account, {
    Future<void> Function()? authorize,
  });

  /// Exact provider-ID matches only: `tt…`, `tmdb:N` or `tvdb:N`.
  Future<List<Map<String, dynamic>>> findItems(
    MediaServerAccount account, {
    required String id,
    required bool isMovie,
    int? season,
    int? episode,
    Future<void> Function()? authorize,
    Object? cacheScope,
    void Function()? onIncomplete,
  });

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
  });

  Future<MediaServerLibraryItem> libraryItem(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });

  Future<Uint8List?> libraryImage(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });

  /// Direct-play original files of one item.
  Future<List<Map<String, dynamic>>> mediaSources(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });

  Future<MediaServerWatchState> watchState(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });

  /// A server-issued playback session id, or null when the client should
  /// generate its own.
  Future<String?> watchSessionId(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });

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
  });

  Future<void> markWatched(
    MediaServerAccount account,
    String itemId, {
    Future<void> Function()? authorize,
  });
}
