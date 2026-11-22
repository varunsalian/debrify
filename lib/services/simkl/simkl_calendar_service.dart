import 'package:flutter/foundation.dart';

import '../../models/trakt/trakt_calendar_entry.dart';
import 'simkl_anime.dart';
import 'simkl_constants.dart';
import 'simkl_service.dart';

/// Builds a Simkl "my upcoming episodes" calendar.
///
/// Simkl has no per-user calendar endpoint (unlike Trakt's
/// `/calendars/my/shows`), so this synthesizes one: fetch the public CDN
/// calendar of ALL upcoming TV episodes, then keep only the ones whose show is
/// in the user's Simkl library. It reuses [TraktCalendarEntry] as the shared
/// display shape (via [TraktCalendarEntry.fromSimklCalendarJson]) so the
/// calendar screen renders both sources identically — deliberately parallel to
/// [TraktCalendarService], not sharing its Trakt-specific fetch/chunk logic
/// (mirrors why the rest of the Simkl integration stays parallel to Trakt).
///
/// Anime comes from a separate file whose entries carry only Simkl ids and
/// the cour's own episode number: an entry is kept when its Simkl title is in
/// the library (which supplies the IMDb id) and the catalog maps the episode
/// to a TVDB season (see [SimklAnimeEpisodes]).
///
/// The public file is a single rolling window (not per-range), so ONE fetch
/// serves any month; the intersected result is cached in memory with a 15-min
/// TTL and reused for every [getRange] call. Returns empty on failure, or
/// throws when asked to be strict (see [getRange]).
class SimklCalendarService {
  SimklCalendarService._();
  static final SimklCalendarService instance = SimklCalendarService._();

  static const Duration _ttl = Duration(minutes: 15);

  List<TraktCalendarEntry>? _cache;
  DateTime? _cachedAt;
  Future<List<TraktCalendarEntry>?>? _inFlight;
  // Bumped on every invalidation (logout). A fetch in flight when invalidate()
  // runs must NOT write its now-stale result (a different account's calendar)
  // into the cache — it compares this generation before caching.
  int _generation = 0;

  /// Fetch the inclusive local-date range `[start, end]`, grouped by local
  /// midnight. Empty buckets are omitted. Returned map keys are
  /// `DateTime(year, month, day)` in local time — matching
  /// [TraktCalendarService.getRange] so the screen can consume either.
  ///
  /// With [strict], a failed read throws instead of looking like an empty
  /// calendar.
  Future<Map<DateTime, List<TraktCalendarEntry>>> getRange(
    DateTime start,
    DateTime end, {
    bool strict = false,
  }) async {
    if (end.isBefore(start)) return <DateTime, List<TraktCalendarEntry>>{};

    final entries = await _loadEntries(strict: strict);
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);

    final grouped = <DateTime, List<TraktCalendarEntry>>{};
    for (final entry in entries) {
      final local = entry.firstAiredLocal;
      final localDay = DateTime(local.year, local.month, local.day);
      if (localDay.isBefore(startDay) || localDay.isAfter(endDay)) continue;
      (grouped[localDay] ??= <TraktCalendarEntry>[]).add(entry);
    }
    return grouped;
  }

  /// Drop the cached calendar. Call on Simkl logout or a user-triggered refresh.
  /// Also drops any in-flight fetch so a completing one can't repopulate the
  /// cache with the just-logged-out account's data.
  void invalidate() {
    _cache = null;
    _cachedAt = null;
    _inFlight = null;
    _generation++;
  }

  /// The intersected, parsed calendar entries — cached with a TTL and
  /// in-flight-coalesced so concurrent month loads share one network fetch.
  Future<List<TraktCalendarEntry>> _loadEntries({bool strict = false}) async {
    List<TraktCalendarEntry> settle(List<TraktCalendarEntry>? result) {
      if (result == null && strict) {
        throw StateError('Simkl calendar read failed');
      }
      return result ?? const <TraktCalendarEntry>[];
    }

    final cache = _cache;
    final at = _cachedAt;
    if (cache != null &&
        at != null &&
        DateTime.now().difference(at) < _ttl) {
      return cache;
    }
    final inFlight = _inFlight;
    if (inFlight != null) return settle(await inFlight);

    final gen = _generation;
    final future = _fetchAndIntersect();
    _inFlight = future;
    try {
      final result = await future;
      // Cache ONLY an authoritative result (null = a fetch failed), and ONLY if
      // no invalidation happened while we were in flight — otherwise a transient
      // failure would pin an empty calendar for 15 min, or a stale fetch would
      // repopulate a just-cleared (e.g. logged-out) cache.
      if (result != null && gen == _generation) {
        _cache = result;
        _cachedAt = DateTime.now();
      }
      return settle(result);
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  /// Returns the intersected entries, or NULL when any fetch failed (so the
  /// caller won't cache it). A genuinely empty library returns an empty list.
  Future<List<TraktCalendarEntry>?> _fetchAndIntersect() async {
    try {
      final library = await _fetchLibraryShowIds();
      if (library == null) return null; // library fetch failed / unauthed
      final libraryImdbIds = library.imdb;
      // Genuinely no shows in the library ⇒ nothing to intersect (authoritative
      // empty — safe to cache).
      if (libraryImdbIds.isEmpty) return const <TraktCalendarEntry>[];

      final [decoded, anime] = await Future.wait([
        SimklService.instance.fetchPublicOrNull(kSimklCalendarTvUrl),
        if (library.animeImdbBySimkl.isEmpty)
          Future.value()
        else
          SimklService.instance.fetchPublicOrNull(kSimklCalendarAnimeUrl),
      ]);
      // CDN fetch failed (expected a JSON array).
      if (decoded is! List) return null;

      final out = <TraktCalendarEntry>[];
      final seen = <String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final entry = TraktCalendarEntry.fromSimklCalendarJson(
          item.cast<String, dynamic>(),
        );
        if (entry == null) continue;
        final imdb = entry.showImdbId;
        if (imdb == null || !libraryImdbIds.contains(imdb)) continue;
        // De-dupe by show+episode (a title can repeat within the file).
        final key = '$imdb-${entry.seasonNumber}-${entry.episodeNumber}';
        if (seen.add(key)) out.add(entry);
      }
      // A failed anime file only leaves anime out.
      if (anime is List) {
        for (final entry in await _animeEntries(
          anime,
          library.animeImdbBySimkl,
        )) {
          final key =
              '${entry.showImdbId}-${entry.seasonNumber}-${entry.episodeNumber}';
          if (seen.add(key)) out.add(entry);
        }
      }
      return out;
    } catch (e) {
      debugPrint('SimklCalendarService: fetch failed: $e');
      return null;
    }
  }

  /// Anime calendar entries for titles in the library, placed in TVDB
  /// numbering under the library's IMDb id. Films and unmapped episodes are
  /// left out; catalog reads are cached per title and bounded.
  Future<List<TraktCalendarEntry>> _animeEntries(
    List<dynamic> anime,
    Map<int, String> imdbBySimkl,
  ) async {
    final matched = [
      for (final item in anime)
        if (item is Map &&
            item['anime_type'] != 'movie' &&
            item['episode'] is Map &&
            imdbBySimkl[SimklAnimeEpisodes.simklIdOf(item['ids'])] != null)
          item,
    ];
    final out = <TraktCalendarEntry>[];
    for (var offset = 0; offset < matched.length; offset += 4) {
      final batch = await Future.wait([
        for (final item in matched.skip(offset).take(4))
          () async {
            // One malformed entry must not take the TV calendar down with it.
            try {
              final simklId = SimklAnimeEpisodes.simklIdOf(item['ids'])!;
              final number = (item['episode'] as Map)['episode'];
              if (number is! int) return null;
              final c = await SimklAnimeEpisodes.tvdbCoordinate(
                simklId,
                number,
              );
              if (c == null) return null;
              return TraktCalendarEntry.fromSimklCalendarJson({
                ...item.cast<String, dynamic>(),
                'date': _animeAirDay(item['date']),
                'ids': {'imdb': imdbBySimkl[simklId]},
                'episode': {'season': c.season, 'episode': c.episode},
              });
            } catch (_) {
              return null;
            }
          }(),
      ]);
      out.addAll(batch.whereType<TraktCalendarEntry>());
    }
    return out;
  }

  /// The anime file's `date` as the day marker the shared parser reads. Unlike
  /// the TV file's nominal midnights, a timed anime date is a real air time in
  /// Japan (`…T01:00:00+09:00` is the previous evening in the Americas), so it
  /// moves to the viewer's own day; a bare midnight stays a day marker.
  static Object? _animeAirDay(Object? date) {
    final at = date is String ? DateTime.tryParse(date) : null;
    if (at == null || (date as String).contains('T00:00:00')) return date;
    final day = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${day.year}-${two(day.month)}-${two(day.day)}T00:00:00';
  }

  /// IMDb ids of every non-dropped show/anime in the user's library, plus each
  /// episodic anime's Simkl id → IMDb id, or NULL when the library fetch
  /// failed / the user isn't authenticated (so the caller treats it as
  /// non-authoritative rather than "no shows"). Reuses SimklService's cached
  /// `all/all` snapshot — one shared fetch, tagged with each item's own
  /// `status` — instead of issuing per-status calls.
  Future<({Set<String> imdb, Map<int, String> animeImdbBySimkl})?>
  _fetchLibraryShowIds() async {
    final data = await SimklService.instance.fetchLibrarySnapshotOrNull();
    if (data == null) return null;
    final ids = <String>{};
    final animeImdbBySimkl = <int, String>{};
    // Only the show/anime buckets matter to an episode calendar (movies have no
    // upcoming episodes).
    for (final bucketKey in const ['shows', 'anime']) {
      final list = data[bucketKey];
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        // Skip titles the user dropped — no new-episode interest.
        if (item['status'] == 'dropped') continue;
        final show = item['show'];
        final idsMap = show is Map ? show['ids'] : null;
        if (idsMap is! Map) continue;
        final imdb = idsMap['imdb'];
        if (imdb is String && imdb.startsWith('tt')) {
          ids.add(imdb);
          final simklId = SimklAnimeEpisodes.simklIdOf(idsMap);
          if (bucketKey == 'anime' &&
              item['anime_type'] != 'movie' &&
              simklId != null) {
            animeImdbBySimkl[simklId] = imdb;
          }
        }
      }
    }
    return (imdb: ids, animeImdbBySimkl: animeImdbBySimkl);
  }
}
