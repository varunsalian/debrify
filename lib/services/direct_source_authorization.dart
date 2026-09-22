import '../models/torrent.dart';
import 'iptv_source_search.dart';
import 'media_server_service.dart';

/// Validate provider capabilities immediately before a direct source is used.
class DirectSourceAuthorization {
  /// Keep the check adjacent to the operation, after any asynchronous setup.
  /// A rejected capability must never reach the supplied network/player call.
  static Future<T> runIfAuthorized<T>(
    Torrent source,
    Future<T> Function() operation,
  ) async {
    await authorize(source);
    return operation();
  }

  static Future<void> authorize(Torrent source) async {
    await IptvSourceSearch.authorize(source);
    await MediaServerService.authorize(source);
  }
}
