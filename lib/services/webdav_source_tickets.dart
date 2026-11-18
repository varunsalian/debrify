import '../models/torrent.dart';

/// Play-time checks for WebDAV rows found by a title's Sources search.
///
/// A row carries its server's sign-in header, so it may only play while the
/// profile that searched still has that server. The search registers a check
/// per row; rows without one (rebuilt from JSON, or from an older search) must
/// be searched again.
final class WebDavSourceTickets {
  const WebDavSourceTickets._();

  static const prefix = 'webdav:';

  static final _checks = Expando<Future<void> Function()>();

  static bool owns(Torrent source) => source.isWebDavSource;

  static void register(Torrent source, Future<void> Function() check) =>
      _checks[source] = check;

  static Future<void> authorize(Torrent source) async {
    if (!owns(source)) return;
    final check = _checks[source];
    if (check == null) {
      throw StateError('Search this WebDAV server again before playing.');
    }
    await check();
  }
}
