import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/media_identity.dart';
import 'simkl_constants.dart';
import 'simkl_episode_codes.dart';

/// Marks a `shows[]` history entry's seasons as TVDB/IMDb numbering, so
/// Simkl routes an anime episode to the cour that holds it (Attack on Titan
/// S3E13 is episode 1 of its "Season 3 Part 2" title). Simkl documents it as
/// a no-op for other shows. Only for numbers the app supplies: numbers read
/// back from Simkl are already in its own numbering.
const Map<String, Object> kSimklTvdbAnimeSeasons = {
  'use_tvdb_anime_seasons': true,
};

/// A TVDB-style season/episode coordinate, the numbering Debrify plays by
/// (IMDb/Cinemeta shows follow TVDB seasons).
typedef SimklTvdbEpisode = ({int season, int episode});

/// Simkl models anime the way AniDB does: one title per broadcast cour, each
/// numbered from episode 1 (Attack on Titan Season 3 Part 2 is its own title),
/// or one absolutely-numbered title (One Piece). Debrify plays IMDb/TVDB
/// seasons, so every anime episode Simkl reports in its own numbering has to
/// be translated. Simkl stores that translation on each catalog episode
/// (`"tvdb": {"season": 3, "episode": 13}` on AoT S3P2 episode 1), served by
/// the public `GET /anime/episodes/{simkl id}` (no user token).
///
/// Writes need no translation: Simkl routes TVDB/IMDb coordinates to the
/// right cour itself (scrobbles always; history writes with
/// `use_tvdb_anime_seasons`).
final class SimklAnimeEpisodes {
  SimklAnimeEpisodes._();

  /// Episode maps are catalog data, bounded. A map is re-read after [_ttl]
  /// (a weekly-airing cour gains episodes); a failed read is not retried for
  /// [_failureTtl], so a down catalog can't stall every refresh.
  static const int _maxCachedTitles = 200;
  static const Duration _ttl = Duration(hours: 6);
  static const Duration _failureTtl = Duration(minutes: 10);
  static final Map<int, ({Map<int, SimklTvdbEpisode>? map, DateTime at})>
  _maps = {};
  static final Map<int, Future<Map<int, SimklTvdbEpisode>?>> _inFlight = {};

  /// The account's anime cours by every id they carry (IMDb, TVDB, Simkl…):
  /// cours share the show's ids, so this lists every cour of a show. Kept
  /// across library refreshes (writes clear the library cache, not this);
  /// cleared with the account ([forgetAccount]).
  static final Map<String, Set<int>> _coursById = {};

  /// Bumped by [forgetAccount]: a read started before then must not record
  /// the previous account's cours ([remember]'s `generation`).
  static int _accountGeneration = 0;
  static int get accountGeneration => _accountGeneration;

  @visibleForTesting
  static void debugReset() {
    _maps.clear();
    _inFlight.clear();
    _coursById.clear();
  }

  /// Ages every cached episode map by [by] (tests of expiry).
  @visibleForTesting
  static void debugAgeMaps(Duration by) {
    for (final MapEntry(:key, :value) in _maps.entries.toList()) {
      _maps[key] = (map: value.map, at: value.at.subtract(by));
    }
  }

  /// Drops what belongs to the signed-in account (not the catalog maps).
  static void forgetAccount() {
    _coursById.clear();
    _accountGeneration++;
  }

  /// Records the episodic anime cours in a library response (an `anime`
  /// bucket of `/sync/all-items`).
  /// [generation] is [accountGeneration] read before the request.
  static void rememberLibrary(Map<String, dynamic>? data, int generation) {
    final anime = data?['anime'];
    if (anime is! List) return;
    for (final raw in anime) {
      if (raw is! Map || raw['anime_type'] == 'movie') continue;
      final content = raw['show'] ?? raw['anime'];
      if (content is Map) remember(content['ids'], generation);
    }
  }

  /// Records one anime cour from its `ids` object, unless the account
  /// changed since [generation] was read.
  static void remember(dynamic ids, int generation) {
    final simklId = simklIdOf(ids);
    if (simklId == null || generation != _accountGeneration) return;
    for (final id in MediaIdentity.aliases(ids)) {
      (_coursById[id] ??= <int>{}).add(simklId);
    }
  }

  /// The known anime cours of show [id] (empty for TV shows).
  static Set<int> coursFor(String id) =>
      _coursById[MediaIdentity.providerId(id)] ?? const <int>{};

  /// The TVDB coordinate of regular episode [number] of Simkl anime title
  /// [simklId], or null when Simkl has no mapping (or the catalog read
  /// failed).
  static Future<SimklTvdbEpisode?> tvdbCoordinate(
    int simklId,
    int number,
  ) async {
    final map = await _mapFor(simklId);
    return map?[number];
  }

  static Future<Map<int, SimklTvdbEpisode>?> _mapFor(int simklId) {
    final cached = _maps[simklId];
    if (cached != null &&
        DateTime.now().difference(cached.at) <
            (cached.map == null ? _failureTtl : _ttl)) {
      // Least recently used goes first when the cache is full.
      _maps
        ..remove(simklId)
        ..[simklId] = cached;
      return Future.value(cached.map);
    }
    return _inFlight[simklId] ??= () async {
      Map<int, SimklTvdbEpisode>? map;
      try {
        final raw = await _getPublic('/anime/episodes/$simklId');
        if (raw is List) map = parseEpisodeMap(raw);
      } catch (_) {
        map = null;
      } finally {
        _inFlight.remove(simklId);
      }
      final previous = _maps.remove(simklId)?.map;
      if (_maps.length >= _maxCachedTitles) _maps.remove(_maps.keys.first);
      // A failed refresh keeps the previous map and retries after
      // [_failureTtl].
      _maps[simklId] = map == null && previous != null
          ? (map: previous, at: DateTime.now().subtract(_ttl - _failureTtl))
          : (map: map, at: DateTime.now());
      return map ?? previous;
    }();
  }

  /// The `/sync/watched` body asking for [cours] by Simkl id (the endpoint
  /// takes at most 100 items with episodes).
  static List<Map<String, Object>> watchedRequest(Set<int> cours) => [
    for (final simkl in cours.take(100))
      {
        'ids': {'simkl': simkl},
      },
  ];

  /// A `/sync/watched?extended=episodes` response for the cours [cours]
  /// (each numbered on its own) as one show item in TVDB numbering:
  /// `{"seasons": [{"number", "episodes": [{"number", "watched", …}]}]}`, the
  /// shape the TV readers parse. Null when the response can't be read, so the
  /// caller falls back to its plain read.
  static Future<Map<String, dynamic>?> watchedAsShow(
    dynamic response,
    Set<int> cours,
  ) async {
    if (response is! List) return null;
    final bySeason = <int, Map<int, Map<String, dynamic>>>{};
    var matched = false;
    for (final item in response) {
      if (item is! Map || item['result'] == 'not_found') continue;
      final simklId = _int(item['simkl']);
      final seasons = item['seasons'];
      if (simklId == null || !cours.contains(simklId)) return null;
      matched = true;
      if (seasons == null) continue;
      if (seasons is! List) return null;
      // Without the cour's map its episodes can't be placed: an answer
      // missing them would look complete, so fall back instead.
      final map = await _mapFor(simklId);
      if (map == null) return null;
      for (final season in seasons) {
        if (season is! Map || season['episodes'] is! List) return null;
        if (_int(season['number']) == 0) continue; // specials: no TVDB map
        for (final episode in season['episodes'] as List) {
          if (episode is! Map) return null;
          final number = _int(episode['number']);
          if (episode['watched'] != true || number == null) continue;
          final c = map[number];
          if (c == null) continue;
          (bySeason[c.season] ??= {})[c.episode] = {
            ...episode.cast<String, dynamic>(),
            'number': c.episode,
          };
        }
      }
    }
    // Every cour not found (no longer in the library): like the plain read.
    if (!matched) return null;
    return {
      'seasons': [
        for (final MapEntry(key: season, value: episodes) in bySeason.entries)
          {'number': season, 'episodes': episodes.values.toList()},
      ],
    };
  }

  /// A `/sync/watched?extended=episodes` response for the cours [cours] as
  /// `/sync/history/remove` `shows` items that remove every watched episode,
  /// specials included, by Simkl id in each cour's own numbering (no TVDB
  /// flag). Null when the response can't be read or no cour was found, so the
  /// caller falls back to its plain read.
  static List<Map<String, dynamic>>? removalItems(
    dynamic response,
    Set<int> cours,
  ) {
    if (response is! List) return null;
    final items = <Map<String, dynamic>>[];
    var matched = false;
    for (final item in response) {
      if (item is! Map || item['result'] == 'not_found') continue;
      final simklId = _int(item['simkl']);
      final seasons = item['seasons'];
      if (simklId == null || !cours.contains(simklId)) return null;
      matched = true;
      if (seasons == null) continue;
      if (seasons is! List) return null;
      final watched = <Map<String, dynamic>>[];
      for (final season in seasons) {
        final number = season is Map ? _int(season['number']) : null;
        if (number == null || season['episodes'] is! List) return null;
        final episodes = <Map<String, int>>[];
        for (final episode in season['episodes'] as List) {
          if (episode is! Map) return null;
          final n = _int(episode['number']);
          if (episode['watched'] == true && n != null) {
            episodes.add({'number': n});
          }
        }
        if (episodes.isNotEmpty) {
          watched.add({'number': number, 'episodes': episodes});
        }
      }
      if (watched.isNotEmpty) {
        items.add({
          'ids': {'simkl': simklId},
          'seasons': watched,
        });
      }
    }
    return matched ? items : null;
  }

  /// The user's watching anime as `shows`-shaped up-next rows: each episodic
  /// anime whose `next_to_watch` (`"E05"`, the cour's own numbering) has a
  /// TVDB mapping is returned with `show` set and `next_to_watch` rewritten to
  /// `"SxxExx"`, so the TV up-next readers place it like any show. Anime
  /// films and unmapped entries are left out. Of several cours of one show in
  /// progress only the most recently watched says where the user is, so the
  /// others are dropped, even when that newest one can't be placed (an older
  /// cour would offer an episode the user is past).
  static Future<List<Map<String, dynamic>>> upNextAsShows(
    List<dynamic> anime,
    int generation,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (final raw in anime) {
      if (raw is! Map || raw['anime_type'] == 'movie') continue;
      final content = raw['show'] ?? raw['anime'];
      final number = SimklEpisodeCodes.absolute(raw['next_to_watch']);
      final simklId = simklIdOf(content is Map ? content['ids'] : null);
      if (content is! Map || number == null || simklId == null) continue;
      remember(content['ids'], generation);
      rows.add({
        ...raw.cast<String, dynamic>(),
        'show': content,
        'next_to_watch': null,
        '_simkl_id': simklId,
        '_number': number,
      });
    }
    String showOf(Map<String, dynamic> row) =>
        MediaIdentity.preferred((row['show'] as Map)['ids']) ??
        'simkl:${row['_simkl_id']}';
    DateTime watchedAt(Map<String, dynamic> row) =>
        DateTime.tryParse('${row['last_watched_at']}') ?? DateTime(0);
    final newest = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final current = newest[showOf(row)];
      if (current == null || watchedAt(row).isAfter(watchedAt(current))) {
        newest[showOf(row)] = row;
      }
    }
    rows.retainWhere((row) => identical(newest[showOf(row)], row));
    // Catalog reads are cached per title; bound the cold-start fan-out.
    for (var offset = 0; offset < rows.length; offset += 4) {
      await Future.wait([
        for (final row in rows.skip(offset).take(4))
          tvdbCoordinate(row['_simkl_id'] as int, row['_number'] as int).then((
            c,
          ) {
            if (c != null) row['next_to_watch'] = _code(c);
          }),
      ]);
    }
    return [
      for (final row in rows)
        if (row['next_to_watch'] != null)
          row
            ..remove('_simkl_id')
            ..remove('_number'),
    ];
  }

  /// Paused sessions from `/sync/playback/{episodes,movies}` with anime
  /// normalized to the TV/movie shape every reader expects: an anime episode
  /// session (container `anime`, the cour's own numbering) gets `show` and an
  /// `episode` in TVDB coordinates (Simkl's `tvdb_season`/`tvdb_number`, or
  /// the catalog mapping); an anime film session gets `movie`. Sessions that
  /// can't be placed are left as they were (readers skip them). Non-anime
  /// sessions pass through untouched.
  static Future<List<dynamic>> normalizePlaybackSessions(
    List<dynamic> sessions,
    int generation,
  ) async {
    if (!hasAnime(sessions)) return sessions;
    final out = <dynamic>[];
    for (final raw in sessions) {
      if (raw is! Map ||
          raw['anime'] is! Map ||
          raw['show'] != null ||
          raw['movie'] != null) {
        out.add(raw);
        continue;
      }
      final anime = raw['anime'] as Map;
      final ep = raw['episode'];
      if (raw['type'] != 'movie') remember(anime['ids'], generation);
      if (raw['type'] == 'movie') {
        out.add({...raw.cast<String, dynamic>(), 'movie': anime});
        continue;
      }
      // A special (season 0) reuses regular episode numbers and has no TVDB
      // season: placing it by number would resume the wrong episode.
      if (ep is! Map ||
          _int(ep['season']) == 0 ||
          _int(ep['tvdb_season'] ?? raw['tvdb_season']) == 0) {
        out.add(raw);
        continue;
      }
      var coordinate =
          tvdbOf({
            'season': ep['tvdb_season'] ?? raw['tvdb_season'],
            'episode': ep['tvdb_number'] ?? raw['tvdb_number'],
          }) ??
          tvdbOf(ep['tvdb']);
      if (coordinate == null) {
        final simklId = simklIdOf(anime['ids']);
        final number = _int(ep['number']);
        if (simklId != null && number != null) {
          coordinate = await tvdbCoordinate(simklId, number);
        }
      }
      if (coordinate == null) {
        out.add(raw);
        continue;
      }
      out.add({
        ...raw.cast<String, dynamic>(),
        'show': anime,
        'episode': {
          ...ep.cast<String, dynamic>(),
          'season': coordinate.season,
          'number': coordinate.episode,
        },
      });
    }
    return out;
  }

  /// Whether a paused-session list holds anime (checked before awaiting
  /// [normalizePlaybackSessions], so TV-only lists take no extra async step).
  static bool hasAnime(List<dynamic> sessions) =>
      sessions.any((raw) => raw is Map && raw['anime'] is Map);

  static String _code(SimklTvdbEpisode c) =>
      'S${c.season.toString().padLeft(2, '0')}'
      'E${c.episode.toString().padLeft(2, '0')}';

  /// A public catalog GET (client id only, no user token); decoded JSON or
  /// null on failure.
  static Future<dynamic> _getPublic(String path) async {
    final uri = Uri.parse('$kSimklApiBaseUrl$path').replace(
      queryParameters: {
        'client_id': kSimklClientId,
        'app-name': kSimklAppName,
        'app-version': kSimklAppVersion,
      },
    );
    final response = await http
        .get(
          uri,
          headers: {'simkl-api-key': kSimklClientId, 'User-Agent': 'Debrify'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      debugPrint('Simkl: anime episodes failed (${response.statusCode})');
      return null;
    }
    return jsonDecode(response.body);
  }

  /// Regular episode number → TVDB coordinate, from a
  /// `/anime/episodes/{id}` response. Specials (`type: special`, season 0)
  /// and episodes without a usable mapping are left out.
  @visibleForTesting
  static Map<int, SimklTvdbEpisode> parseEpisodeMap(List<dynamic> raw) {
    final map = <int, SimklTvdbEpisode>{};
    for (final entry in raw) {
      if (entry is! Map || entry['type'] == 'special') continue;
      final number = _int(entry['episode']);
      final coordinate = tvdbOf(entry['tvdb']);
      if (number == null || number <= 0 || coordinate == null) continue;
      map[number] = coordinate;
    }
    return map;
  }

  /// A `{"season": n, "episode": m}` block as a regular-season coordinate.
  static SimklTvdbEpisode? tvdbOf(dynamic block) {
    if (block is! Map) return null;
    final season = _int(block['season']);
    final episode = _int(block['episode']);
    if (season == null || season <= 0 || episode == null || episode <= 0) {
      return null;
    }
    return (season: season, episode: episode);
  }

  /// The Simkl title id in an `ids` object (`simkl`, or the calendar
  /// files' `simkl_id`).
  static int? simklIdOf(dynamic ids) =>
      ids is Map ? _int(ids['simkl'] ?? ids['simkl_id']) : null;

  static int? _int(dynamic value) => switch (value) {
    int v => v,
    num v => v.toInt(),
    String v => int.tryParse(v),
    _ => null,
  };
}
