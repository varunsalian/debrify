// Cached, request-deduplicating access to the public sports feeds.
//
// Data layer: HTTP happens only through the injected [SportsFetch] contract
// and every timestamp comes from the injected clock, so tests run offline and
// on fake time. One client is shared by the board controller; the cache is
// keyed per request URI, expires on a live/schedule TTL, keeps serving stale
// entries when a refresh fails, and shares one in-flight fetch per URI.
//
// ESPN is requested one UTC day at a time: its scoreboard rejects
// `dates=YYYYMMDD-YYYYMMDD` ranges with HTTP 400 (observed 2026-10-29), and
// a whole-month request is ~3 MB of JSON per US league, too heavy to parse
// on a TV box. Day entries are cached individually, so "Today" and "This
// week" share them, and at most [SportsFeedClient.maxConcurrentFetches]
// requests are in flight at once.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';

import 'espn_scoreboard_parser.dart';
import 'jolpica_f1_parser.dart';

/// Fetches a feed body as text; production wires `httpSportsFetch`.
typedef SportsFetch = Future<String> Function(Uri uri);

/// A feed could not be produced, at either the transport or the JSON level.
class SportsFeedException implements Exception {
  SportsFeedException(this.uri, this.message);

  final Uri uri;
  final String message;

  @override
  String toString() => 'SportsFeedException($uri): $message';
}

/// One successfully parsed feed body and when it was fetched.
class _CacheEntry {
  const _CacheEntry({required this.events, required this.fetchedAt});

  final List<SportsEvent> events;
  final DateTime fetchedAt;
}

/// Loads [SportsEvent]s for the supported leagues behind one cache.
class SportsFeedClient {
  SportsFeedClient({
    required SportsFetch fetch,
    DateTime Function()? clock,
    this.scheduleTtl = const Duration(minutes: 15),
    this.liveTtl = const Duration(seconds: 90),
  }) : _fetch = fetch,
       _clock = clock ?? DateTime.now;

  static const String _espnBase =
      'https://site.api.espn.com/apis/site/v2/sports';

  /// Whole current season; the per-call window trims it.
  static final Uri jolpicaSeasonUri = Uri.parse(
    'https://api.jolpi.ca/ergast/f1/current.json',
  );

  static const String _f1LeagueId = 'f1';

  /// How far before `fromUtc` an F1 race may still appear on the board.
  static const Duration _f1Lead = Duration(hours: 3);

  /// Longest window [fetchLeague] expands into per-day ESPN requests.
  static const int maxWindowDays = 16;

  /// Cap on simultaneous feed requests across all leagues and days.
  static const int maxConcurrentFetches = 8;

  final SportsFetch _fetch;
  final DateTime Function() _clock;
  int _activeFetches = 0;
  final Queue<Completer<void>> _fetchWaiters = Queue<Completer<void>>();

  /// TTL for a cached list that contains no live event.
  final Duration scheduleTtl;

  /// TTL for a cached list that contains at least one live event.
  final Duration liveTtl;

  final Map<Uri, _CacheEntry> _cache = {};
  final Map<Uri, Future<List<SportsEvent>>> _inFlight = {};

  /// ESPN scoreboard URIs for [league] covering `[fromUtc, toUtc]`: one per
  /// UTC calendar day, in order, at most [maxWindowDays]. Throws
  /// [ArgumentError] for leagues without an ESPN feed or a window that ends
  /// before it starts.
  static List<Uri> espnScoreboardUris(
    SportsLeague league,
    DateTime fromUtc,
    DateTime toUtc,
  ) {
    final first = _utcDay(fromUtc);
    final last = _utcDay(toUtc);
    if (last.isBefore(first)) {
      throw ArgumentError.value(toUtc, 'toUtc', 'is before fromUtc');
    }
    return [
      for (
        var day = first, n = 0;
        !day.isAfter(last) && n < maxWindowDays;
        day = day.add(const Duration(days: 1)), n++
      )
        espnScoreboardUri(league, day),
    ];
  }

  /// ESPN scoreboard URI for [league] on the UTC calendar day of [dayUtc].
  /// Throws [ArgumentError] for leagues without an ESPN feed.
  static Uri espnScoreboardUri(SportsLeague league, DateTime dayUtc) {
    final path = league.espnPath;
    if (path == null) {
      throw ArgumentError.value(
        league.id,
        'league',
        'has no ESPN scoreboard feed',
      );
    }
    return Uri.parse(
      '$_espnBase/$path/scoreboard'
      '?dates=${_compactUtcDate(dayUtc)}&limit=200',
    );
  }

  /// Events for [league] whose feed covers `[fromUtc, toUtc]`.
  ///
  /// Per request URI (the F1 season, or one ESPN UTC day): serves a fresh
  /// cache entry unless [force] is set, shares one in-flight fetch, and falls
  /// back to the stale entry when the fetch or the JSON body fails. Days that
  /// fail with nothing cached are left out; [SportsFeedException] is thrown
  /// only when every day failed. Returned lists are sorted by start, then id.
  Future<List<SportsEvent>> fetchLeague(
    SportsLeague league, {
    required DateTime fromUtc,
    required DateTime toUtc,
    bool force = false,
  }) async {
    if (league.id == _f1LeagueId) {
      final season = await _entry(league, jolpicaSeasonUri, force);
      return _window(season, league, fromUtc, toUtc);
    }
    if (league.espnPath == null) return const [];
    final days = espnScoreboardUris(league, fromUtc, toUtc);
    final results = await Future.wait([
      for (final uri in days)
        _entry(
          league,
          uri,
          force,
        ).then<Object>((events) => events, onError: (Object e) => e),
    ]);
    final byId = <String, SportsEvent>{};
    Object? failure;
    var succeeded = 0;
    for (final result in results) {
      if (result is List<SportsEvent>) {
        succeeded++;
        for (final event in result) {
          byId[event.id] = event;
        }
      } else {
        failure ??= result;
      }
    }
    if (failure != null) {
      // A partly failed window still shows the days that loaded; keep a trace
      // of why the rest are missing.
      debugPrint('Sports: ${league.id} feed day failed: $failure');
    }
    if (succeeded == 0 && failure != null) {
      if (failure is SportsFeedException) throw failure;
      throw SportsFeedException(days.first, '$failure');
    }
    return byId.values.toList()..sort(_byStartThenId);
  }

  /// One URI's events: fresh cache, the shared in-flight fetch, or a new one.
  Future<List<SportsEvent>> _entry(
    SportsLeague league,
    Uri uri,
    bool force,
  ) async {
    if (!force) {
      final cached = _cache[uri];
      if (cached != null && _isFresh(cached)) {
        return List<SportsEvent>.of(cached.events);
      }
    }
    return List<SportsEvent>.of(await _pendingOrStart(league, uri));
  }

  /// [_fetch] behind the [maxConcurrentFetches] cap. Waiters are woken in
  /// arrival order, though a new caller can take a freed slot first; the cap
  /// itself always holds.
  Future<String> _limitedFetch(Uri uri) async {
    while (_activeFetches >= maxConcurrentFetches) {
      final turn = Completer<void>();
      _fetchWaiters.add(turn);
      await turn.future;
    }
    _activeFetches++;
    try {
      return await _fetch(uri);
    } finally {
      _activeFetches--;
      if (_fetchWaiters.isNotEmpty) _fetchWaiters.removeFirst().complete();
    }
  }

  Future<List<SportsEvent>> _pendingOrStart(SportsLeague league, Uri uri) {
    final pending = _inFlight[uri];
    if (pending != null) return pending;
    final started = _load(league, uri);
    _inFlight[uri] = started;
    return started.whenComplete(() => _inFlight.remove(uri));
  }

  /// One fetch + parse cycle; success updates the cache, failure either
  /// serves the stale entry or throws.
  Future<List<SportsEvent>> _load(SportsLeague league, Uri uri) async {
    List<SportsEvent>? events;
    Object? failure;
    try {
      events = _parseBody(await _limitedFetch(uri), uri, league);
    } catch (error) {
      failure = error;
    }
    if (events != null) {
      _cache[uri] = _CacheEntry(events: events, fetchedAt: _clock());
      return events;
    }
    final stale = _cache[uri];
    if (stale != null) return stale.events;
    if (failure is SportsFeedException) throw failure;
    throw SportsFeedException(uri, '$failure');
  }

  List<SportsEvent> _parseBody(String body, Uri uri, SportsLeague league) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException catch (error) {
      throw SportsFeedException(
        uri,
        'response body was not JSON: ${error.message}',
      );
    }
    final events = league.id == _f1LeagueId
        ? parseJolpicaSeason(json, now: _clock())
        : parseEspnScoreboard(json, leagueId: league.id);
    return List<SportsEvent>.of(events)..sort(_byStartThenId);
  }

  /// The F1 cache holds the whole season; every call re-applies its window.
  List<SportsEvent> _window(
    List<SportsEvent> events,
    SportsLeague league,
    DateTime fromUtc,
    DateTime toUtc,
  ) {
    if (league.id != _f1LeagueId) return List<SportsEvent>.of(events);
    final first = fromUtc.subtract(_f1Lead);
    return events
        .where(
          (event) =>
              !event.start.isBefore(first) && !event.start.isAfter(toUtc),
        )
        .toList();
  }

  bool _isFresh(_CacheEntry entry) {
    final now = _clock();
    // Live scores, and fixtures whose kick-off has arrived but are still
    // listed as scheduled, use the short lifetime so they turn live promptly.
    final hot = entry.events.any(
      (event) => _isLive(event) || _isDue(event, now),
    );
    return now.difference(entry.fetchedAt) < (hot ? liveTtl : scheduleTtl);
  }

  static bool _isDue(SportsEvent event, DateTime now) =>
      event.status == SportsEventStatus.scheduled &&
      !event.start.isAfter(now.toUtc()) &&
      now.toUtc().difference(event.start) < const Duration(hours: 3);

  static bool _isLive(SportsEvent event) =>
      event.status == SportsEventStatus.live;

  static DateTime _utcDay(DateTime instant) {
    final utc = instant.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  static String _compactUtcDate(DateTime instant) {
    final utc = instant.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    return '${utc.year}$month$day';
  }
}

int _byStartThenId(SportsEvent a, SportsEvent b) {
  final byStart = a.start.compareTo(b.start);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}
