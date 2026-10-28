// The user's own IPTV guide, read straight out of the catalog database.
//
// Data layer: the production [SportsGuideSource]. The whole scan lives in
// [querySportsGuide] — synchronous, plain data in and out — so `load` can push
// it to a background isolate and a 50k-channel catalog never blocks the UI.
// The database is opened read-only: browsing sport never writes to the catalog.
import 'dart:convert';

import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/services/xmltv_epg_source.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

/// One IPTV playlist a guide query should run against.
@immutable
class SportsGuidePlaylist {
  const SportsGuidePlaylist({
    required this.playlistId,
    required this.catalogKey,
    this.guideKey,
  });

  /// Identity carried on every channel this query returns.
  final String playlistId;

  /// `catalogs.catalog_key` holding this playlist's channels.
  final String catalogKey;

  /// `epg_guides.guide_key`; null when the playlist has no EPG.
  final String? guideKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsGuidePlaylist &&
          other.playlistId == playlistId &&
          other.catalogKey == catalogKey &&
          other.guideKey == guideKey);

  @override
  int get hashCode => Object.hash(playlistId, catalogKey, guideKey);

  @override
  String toString() =>
      'SportsGuidePlaylist($playlistId, $catalogKey, $guideKey)';
}

/// Supplies guide data from Debrify's IPTV catalog database.
class SqliteSportsGuideSource implements SportsGuideSource {
  SqliteSportsGuideSource({required this.dbPath, required this.playlists});

  /// Resolved per query so a profile switch is picked up on the next load.
  final String Function() dbPath;

  /// The playlists to scan, resolved per query by the composition boundary.
  final Future<List<SportsGuidePlaylist>> Function() playlists;

  @override
  Future<SportsGuideSnapshot> load(SportsGuideQuery query) async {
    // Both sides of the hand-off are captured before the await: an old path
    // must never be paired with newly resolved playlists (or vice versa).
    final path = dbPath();
    final targets = await playlists();
    if (targets.isEmpty) return SportsGuideSnapshot.empty;
    final _GuideQueryArgs args = (
      dbPath: path,
      playlists: targets,
      query: query,
    );
    return compute(_runGuideQuery, args);
  }
}

/// Synchronous worker body; plain data in and out so it can run in compute().
///
/// A database that cannot be opened at all is a real failure and propagates.
/// Once open, one playlist failing never fails the whole query.
SportsGuideSnapshot querySportsGuide(
  String dbPath,
  List<SportsGuidePlaylist> playlists,
  SportsGuideQuery query,
) {
  final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
  try {
    db.execute('PRAGMA busy_timeout = 3000');
    final accumulator = _GuideAccumulator(query);
    for (final playlist in playlists) {
      try {
        accumulator.addPlaylist(db, playlist);
      } on SqliteException {
        // A playlist whose tables cannot be read contributes nothing; the
        // other playlists keep answering for this board.
      }
    }
    return accumulator.snapshot();
  } finally {
    db.dispose();
  }
}

typedef _GuideQueryArgs = ({
  String dbPath,
  List<SportsGuidePlaylist> playlists,
  SportsGuideQuery query,
});

SportsGuideSnapshot _runGuideQuery(_GuideQueryArgs args) =>
    querySportsGuide(args.dbPath, args.playlists, args.query);

/// One live channel plus the derived keys the guide query needs.
class _GuideChannel {
  _GuideChannel(this.ref, this.baseName);

  final SportsChannelRef ref;
  final String baseName;

  /// Filled once the playlist's guide is known: every `epg_programmes`
  /// channel id this channel can appear under, best guess first.
  final List<String> guideIds = [];

  bool get isSportsGroup => (ref.group ?? '').toLowerCase().contains('sport');
}

/// Collects the three result sets of one query across every playlist, applying
/// the global caps so a huge catalog cannot produce a huge snapshot.
class _GuideAccumulator {
  _GuideAccumulator(this._query);

  final SportsGuideQuery _query;
  final List<SportsChannelRef> _channels = [];
  final List<SportsGuideListing> _listings = [];
  final List<SportsGuideListing> _liveSports = [];

  SportsGuideSnapshot snapshot() => SportsGuideSnapshot(
    listings: List<SportsGuideListing>.unmodifiable(_listings),
    channels: List<SportsChannelRef>.unmodifiable(_channels),
    liveSportsListings: List<SportsGuideListing>.unmodifiable(_liveSports),
  );

  void addPlaylist(Database db, SportsGuidePlaylist playlist) {
    final generation = _currentGeneration(db, playlist.catalogKey);
    if (generation == null) return;
    final channels = _liveChannels(db, playlist, generation);
    _addChannels(channels);
    final guideKey = playlist.guideKey;
    if (guideKey == null) return;
    final nameToId = _guideNameToId(db, guideKey);
    if (nameToId == null) return;
    for (final channel in channels) {
      channel.guideIds.addAll(_guideIds(channel, nameToId));
    }
    _addListings(db, guideKey, channels);
    _addLiveSports(db, guideKey, channels);
  }

  /// The catalog's current generation, null when the catalog has no row.
  int? _currentGeneration(Database db, String catalogKey) {
    final rows = db.select(
      'SELECT generation FROM catalogs WHERE catalog_key = ?',
      [catalogKey],
    );
    if (rows.isEmpty) return null;
    return rows.first['generation'] as int?;
  }

  /// Live rows of one catalog generation: an explicit `content_type` wins,
  /// otherwise only untimed (or non-positive duration) rows are live.
  static const _channelSql = """
    SELECT name, url, logo_url, grp, attributes_json, http_headers_json
    FROM channels
    WHERE catalog_key = ? AND generation = ?
      AND (CASE WHEN content_type IS NOT NULL THEN content_type = 'live'
                ELSE (duration IS NULL OR duration <= 0) END)
    ORDER BY position
  """;

  List<_GuideChannel> _liveChannels(
    Database db,
    SportsGuidePlaylist playlist,
    int generation,
  ) {
    final rows = db.select(_channelSql, [playlist.catalogKey, generation]);
    return [
      for (final row in rows)
        _GuideChannel(
          SportsChannelRef(
            name: row['name'] as String? ?? '',
            url: row['url'] as String? ?? '',
            logoUrl: row['logo_url'] as String?,
            group: row['grp'] as String?,
            playlistId: playlist.playlistId,
            attributes: _stringMap(row['attributes_json'] as String?),
            httpHeaders: _stringMap(row['http_headers_json'] as String?),
          ),
          channelBaseName(row['name'] as String? ?? ''),
        ),
    ];
  }

  void _addChannels(List<_GuideChannel> channels) {
    for (final channel in channels) {
      if (_channels.length >= _maxChannels) return;
      if (channel.baseName.isEmpty ||
          !_matchesChannelNeedle(channel.baseName)) {
        continue;
      }
      _channels.add(channel.ref);
    }
  }

  /// A broadcaster needle matches its own base name and its numbered siblings
  /// (`'tnt sports 2'`, `'tnt sports 10'`), never a differently named sibling
  /// such as `'tnt sports extra'`.
  bool _matchesChannelNeedle(String baseName) {
    for (final needle in _query.channelNeedles) {
      if (needle.isEmpty) continue;
      if (baseName == needle) return true;
      if (!baseName.startsWith('$needle ')) continue;
      if (_digits.hasMatch(baseName.substring(needle.length + 1))) return true;
    }
    return false;
  }

  /// `name_to_id_json` of the playlist's guide row; null when there is no row.
  Map<String, String>? _guideNameToId(Database db, String guideKey) {
    final rows = db.select(
      'SELECT name_to_id_json FROM epg_guides WHERE guide_key = ?',
      [guideKey],
    );
    if (rows.isEmpty) return null;
    return _stringMap(rows.first['name_to_id_json'] as String?);
  }

  /// The guide ids [channel] can appear under: tvg-id (also without its
  /// `@suffix`), then the name→id map for tvg-name, then for the name itself.
  List<String> _guideIds(_GuideChannel channel, Map<String, String> nameToId) {
    final tvgId = (channel.ref.attributes['tvg-id'] ?? '').trim().toLowerCase();
    if (tvgId.isNotEmpty) {
      final atSign = tvgId.indexOf('@');
      final bare = atSign < 0 ? tvgId : tvgId.substring(0, atSign);
      if (bare.isEmpty || bare == tvgId) return [tvgId];
      return [tvgId, bare];
    }
    final tvgName = (channel.ref.attributes['tvg-name'] ?? '').trim();
    if (tvgName.isNotEmpty) {
      final byTvgName = nameToId[XmltvEpgSource.normalizeChannelName(tvgName)];
      if (byTvgName != null) return [byTvgName];
    }
    final byName =
        nameToId[XmltvEpgSource.normalizeChannelName(channel.ref.name)];
    return byName == null ? const <String>[] : [byName];
  }

  void _addListings(Database db, String guideKey, List<_GuideChannel> all) {
    final tokens = _titleTokens(_query.titleNeedles);
    if (tokens.isEmpty) return;
    final byChannelId = <String, List<_GuideChannel>>{};
    for (final channel in all) {
      for (final id in channel.guideIds) {
        byChannelId.putIfAbsent(id, () => <_GuideChannel>[]).add(channel);
      }
    }
    if (byChannelId.isEmpty) return;
    // A row can satisfy a token in two chunks; it must list once per channel.
    final seen = <String>{};
    for (var start = 0; start < tokens.length; start += _tokenChunk) {
      if (_listings.length >= _maxListings) return;
      final end = _clampEnd(start, tokens.length, _tokenChunk);
      final like = List.filled(end - start, 'lower(title) LIKE ?').join(' OR ');
      final rows = db.select(
        'SELECT channel_id, start_ms, stop_ms, title FROM epg_programmes '
        'WHERE guide_key = ? AND stop_ms > ? AND start_ms < ? AND ($like)',
        [
          guideKey,
          _toMillis(_query.fromUtc),
          _toMillis(_query.toUtc),
          for (var i = start; i < end; i++) '%${tokens[i]}%',
        ],
      );
      for (final row in rows) {
        final channelId = row['channel_id'] as String? ?? '';
        final channels = byChannelId[channelId];
        if (channels == null) continue;
        final title = row['title'] as String? ?? '';
        if (!seen.add('$channelId|${row['start_ms']}|$title')) continue;
        if (!_titleContainsNeedle(title)) continue;
        for (final channel in channels) {
          if (_listings.length >= _maxListings) return;
          _listings.add(_listing(channel.ref, title, row));
        }
      }
    }
  }

  /// Programmes airing now on sports-group channels, in channel position order.
  void _addLiveSports(Database db, String guideKey, List<_GuideChannel> all) {
    final sports = <_GuideChannel>[];
    for (final channel in all) {
      if (sports.length >= _maxSportsChannels) break;
      if (channel.isSportsGroup) sports.add(channel);
    }
    final ids = <String>{for (final channel in sports) ...channel.guideIds};
    if (ids.isEmpty) return;
    final rowsById = _rowsAiringNow(db, guideKey, ids.toList(), _query.nowUtc);
    final seenBases = <String>{};
    for (final channel in sports) {
      if (_liveSports.length >= _maxLiveSports) return;
      // Copies of one channel (4K/HD) share a base name: position wins.
      if (channel.baseName.isNotEmpty && !seenBases.add(channel.baseName)) {
        continue;
      }
      final emitted = <String>{};
      for (final id in channel.guideIds) {
        for (final row in rowsById[id] ?? const <Row>[]) {
          if (_liveSports.length >= _maxLiveSports) return;
          final title = row['title'] as String? ?? '';
          if (!emitted.add('${row['start_ms']}|$title')) continue;
          _liveSports.add(_listing(channel.ref, title, row));
        }
      }
    }
  }

  Map<String, List<Row>> _rowsAiringNow(
    Database db,
    String guideKey,
    List<String> ids,
    DateTime nowUtc,
  ) {
    final now = _toMillis(nowUtc);
    final rowsById = <String, List<Row>>{};
    for (var start = 0; start < ids.length; start += _idChunk) {
      final end = _clampEnd(start, ids.length, _idChunk);
      final placeholders = List.filled(end - start, '?').join(', ');
      final rows = db.select(
        'SELECT channel_id, start_ms, stop_ms, title FROM epg_programmes '
        'WHERE guide_key = ? AND channel_id IN ($placeholders) '
        'AND start_ms <= ? AND stop_ms > ?',
        [guideKey, ...ids.sublist(start, end), now, now],
      );
      for (final row in rows) {
        rowsById
            .putIfAbsent(row['channel_id'] as String? ?? '', () => <Row>[])
            .add(row);
      }
    }
    for (final rows in rowsById.values) {
      rows.sort(
        (a, b) => _columnMillis(
          a['start_ms'],
        ).compareTo(_columnMillis(b['start_ms'])),
      );
    }
    return rowsById;
  }

  bool _titleContainsNeedle(String title) {
    final normalized = normalizeSportsText(title);
    return _query.titleNeedles.any(
      (needle) => sportsTextContains(normalized, needle),
    );
  }

  SportsGuideListing _listing(
    SportsChannelRef channel,
    String title,
    Row row,
  ) => SportsGuideListing(
    channel: channel,
    title: title,
    start: _utc(row['start_ms']),
    stop: _utc(row['stop_ms']),
  );
}

/// One LIKE token per needle: its longest word (ties → first) of 4+ characters.
List<String> _titleTokens(List<String> needles) {
  final tokens = <String>[];
  for (final needle in needles) {
    var longest = '';
    for (final word in needle.split(' ')) {
      if (word.length > longest.length) longest = word;
    }
    if (longest.length < _minTokenLength) continue;
    final token = _accentTolerant(longest);
    if (!tokens.contains(token)) tokens.add(token);
  }
  return tokens;
}

/// Needles are accent-folded but guide titles are not ("München",
/// "Atlético"), so letters that have accented forms become LIKE's
/// single-character wildcard. This only widens the SQL pre-filter; every row
/// is still checked against the full needle after normalization.
String _accentTolerant(String word) {
  final token = word.replaceAll(RegExp('[aeiouync]'), '_');
  final literal = token.replaceAll('_', '').length;
  return literal >= 2 ? token : word;
}

/// A JSON object of string→string. NULL, a non-object or a malformed blob is
/// an empty map: an unusable attribute block is not worth losing a channel.
Map<String, String> _stringMap(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const {};
  final Object? decoded;
  try {
    decoded = jsonDecode(encoded);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final values = <String, String>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key is String && value is String) values[key] = value;
  }
  return values;
}

int _clampEnd(int start, int length, int chunk) =>
    start + chunk < length ? start + chunk : length;

DateTime _utc(Object? milliseconds) => DateTime.fromMillisecondsSinceEpoch(
  _columnMillis(milliseconds),
  isUtc: true,
);

int _columnMillis(Object? value) => value is num ? value.toInt() : 0;

int _toMillis(DateTime value) => value.toUtc().millisecondsSinceEpoch;

final RegExp _digits = RegExp(r'^[0-9]+$');

const int _minTokenLength = 4;
const int _tokenChunk = 40;
const int _idChunk = 400;
const int _maxChannels = 200;
const int _maxListings = 2000;
const int _maxLiveSports = 40;
const int _maxSportsChannels = 300;
