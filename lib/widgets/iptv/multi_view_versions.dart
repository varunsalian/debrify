// Other versions of a multi-view channel, from every IPTV playlist of the
// active profile: the HD copy of a 4K channel the box cannot decode next to
// another 4K tile, or another provider's copy of a stream that will not play.
// Glue between multi-view and the catalog database (read-only, off the UI
// isolate, like the Sports board's guide query).
import 'dart:convert';

import 'package:debrify/features/iptv_multiview/models/channel_versions.dart';
import 'package:debrify/features/sports/data/iptv_sports_guide_playlists.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// The versions of [channel] worth trying, best first (see
/// [orderChannelVersions]); empty when there are none or the catalog cannot
/// be read.
Future<List<IptvChannel>> findMultiViewVersions(IptvChannel channel) async {
  final base = channelIdentity(channel.name).base;
  if (base.isEmpty || !IptvCatalogDb.isOpen) return const [];
  try {
    final path = IptvCatalogDb.path;
    final playlists = await loadIptvSportsGuidePlaylists();
    if (playlists.isEmpty) return const [];
    final rows = await compute(_queryVersions, (
      dbPath: path,
      catalogs: [
        for (final p in playlists)
          // Categories the profile hid stay hidden here too.
          (
            p.playlistId,
            p.catalogKey,
            IptvCatalogDb.hiddenGroups(p.catalogKey),
          ),
      ],
      // The base's words, in order, anywhere in the name: narrows the scan
      // before the exact comparison in Dart (shortest names first, so
      // "ELEVEN SPORTS 1" copies come before "ELEVEN SPORTS 10 …"). LIKE
      // folds only ASCII case, so other scripts' words are left to Dart.
      pattern: [
        '',
        for (final word in base.split(' '))
          if (RegExp(r'^[a-z0-9+]+$').hasMatch(word)) word,
        '',
      ].join('%'),
    ));
    final candidates = [
      for (final row in rows)
        IptvChannel(
          name: row.name,
          url: row.url,
          logoUrl: row.logo,
          group: row.group,
          contentType: 'live',
          attributes: {...row.attributes, 'list_playlist_id': row.playlistId},
          httpHeaders: row.headers,
        ),
    ];
    return orderChannelVersions(
      name: channel.name,
      url: channel.url,
      candidates: candidates,
      nameOf: (c) => c.name,
      urlOf: (c) => c.url,
    );
  } catch (error) {
    debugPrint('Multi-view: versions unavailable (${error.runtimeType})');
    return const [];
  }
}

typedef _Args = ({
  String dbPath,
  List<(String, String, Set<String>)> catalogs,
  String pattern,
});

typedef _Row = ({
  String playlistId,
  String name,
  String url,
  String? logo,
  String? group,
  Map<String, String> attributes,
  Map<String, String> headers,
});

const _sql = """
  SELECT name, url, logo_url, grp, attributes_json, http_headers_json
  FROM channels
  WHERE catalog_key = ? AND generation = ? AND name LIKE ?
    AND (CASE WHEN content_type IS NOT NULL THEN content_type = 'live'
              ELSE (duration IS NULL OR duration <= 0) END)
  ORDER BY length(name)
  LIMIT 500
""";

List<_Row> _queryVersions(_Args args) {
  final db = sqlite3.open(args.dbPath, mode: OpenMode.readOnly);
  try {
    db.execute('PRAGMA busy_timeout = 3000');
    final out = <_Row>[];
    for (final (playlistId, catalogKey, hidden) in args.catalogs) {
      try {
        final generation = db.select(
          'SELECT generation FROM catalogs WHERE catalog_key = ?',
          [catalogKey],
        );
        if (generation.isEmpty) continue;
        for (final row in db.select(_sql, [
          catalogKey,
          generation.first['generation'],
          args.pattern,
        ])) {
          if (hidden.contains(row['grp'])) continue;
          out.add((
            playlistId: playlistId,
            name: row['name'] as String? ?? '',
            url: row['url'] as String? ?? '',
            logo: row['logo_url'] as String?,
            group: row['grp'] as String?,
            attributes: _stringMap(row['attributes_json'] as String?),
            headers: _stringMap(row['http_headers_json'] as String?),
          ));
        }
      } on SqliteException {
        // One unreadable catalog never hides the others' versions.
      }
    }
    return out;
  } finally {
    db.dispose();
  }
}

Map<String, String> _stringMap(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const {};
  try {
    final decoded = jsonDecode(encoded);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.key is String && entry.value is String)
          entry.key as String: entry.value as String,
    };
  } on FormatException {
    return const {};
  }
}
