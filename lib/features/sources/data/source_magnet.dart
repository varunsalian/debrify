import '../../../models/torrent.dart';
import '../../../services/torrent_file_service.dart';

/// Preserve magnet, hash, torrent conversion and RD URL fallback precedence.
Future<String?> sourceMagnet(Torrent t) async {
  final magnet = t.magnetUrl;
  if (magnet != null && magnet.startsWith('magnet:')) return magnet;
  if (t.hasRealInfoHash && t.infohash.isNotEmpty) {
    return 'magnet:?xt=urn:btih:${t.infohash}&dn=${Uri.encodeComponent(t.name)}';
  }
  final torrentUrl = t.torrentUrl;
  if (torrentUrl != null && torrentUrl.isNotEmpty) {
    try {
      return await TorrentFileService.magnetFromTorrentUrl(
        torrentUrl,
        fallbackName: t.name,
      );
    } catch (_) {
      return torrentUrl; // last resort (RD can still consume an http .torrent)
    }
  }
  return null;
}
