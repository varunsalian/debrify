// Resolves which saved IPTV playlists the Sports guide search runs against,
// using the same guide URL rules as the IPTV screen (iptv_guide_context.dart):
// a configured guide URL wins, Xtream panels use their xmltv.php, plain M3U
// playlists use the guide their catalog declared.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:debrify/features/sports/data/sqlite_sports_guide_source.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:sqlite3/sqlite3.dart';

/// Saved playlists that have an ingested live catalog, with the stored guide
/// each one uses. Never throws: an unreadable playlist list or database
/// yields fewer (or no) playlists, which the board shows as "no listing".
Future<List<SportsGuidePlaylist>> loadIptvSportsGuidePlaylists() async {
  if (!IptvCatalogDb.isOpen) return const [];
  final List<IptvPlaylist> saved;
  try {
    saved = await IptvPlaylistStorage.getIptvPlaylists();
  } catch (_) {
    return const [];
  }
  final out = <SportsGuidePlaylist>[];
  for (final playlist in saved) {
    if (playlist.isVirtual || playlist.isLocalFile) continue;
    final catalogKey = IptvCatalogKey.forPlaylist(playlist, 'live');
    if (catalogKey == null) continue;
    final epgUrl = _guideUrlFor(playlist, catalogKey);
    out.add(
      SportsGuidePlaylist(
        playlistId: playlist.id,
        catalogKey: catalogKey,
        guideKey: epgUrl == null
            ? null
            : md5.convert(utf8.encode(epgUrl)).toString(),
      ),
    );
  }
  return out;
}

String? _guideUrlFor(IptvPlaylist playlist, String catalogKey) {
  final manual = playlist.epgUrl?.trim();
  if (manual != null && manual.isNotEmpty) return manual;
  if (playlist.isXtreamCodes) {
    return IptvEpgService.xmltvUrlFor(
      playlist.serverUrl!,
      playlist.username ?? '',
      playlist.password ?? '',
    );
  }
  return _declaredGuideUrl(catalogKey);
}

/// The guide URL an M3U catalog declared in its header, as ingested.
String? _declaredGuideUrl(String catalogKey) {
  Database? db;
  try {
    db = sqlite3.open(IptvCatalogDb.path, mode: OpenMode.readOnly);
    db.execute('PRAGMA busy_timeout = 3000');
    final rows = db.select(
      'SELECT epg_url FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    final url = rows.isEmpty ? null : (rows.first['epg_url'] as String?);
    final trimmed = url?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  } catch (_) {
    return null;
  } finally {
    db?.dispose();
  }
}
