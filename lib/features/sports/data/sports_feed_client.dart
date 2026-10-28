// Cached, request-deduplicating access to the public sports feeds.
//
// Data layer: HTTP happens only through the injected [SportsFetch] contract
// and every timestamp comes from the injected clock, so tests run offline and
// on fake time. One client is shared by the board controller; the cache is
// keyed per request URI, expires on a live/schedule TTL, keeps serving stale
// entries when a refresh fails, and shares one in-flight fetch per URI.
import 'dart:convert';

import 'package:debrify/features/sports/models/sports_models.dart';

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

  final SportsFetch _fetch;
  final DateTime Function() _clock;

  /// TTL for a cached list that contains no live event.
  final Duration scheduleTtl;

  /// TTL for a cached list that contains at least one live event.
  final Duration liveTtl;

  final Map<Uri, _CacheEntry> _cache = {};
  final Map<Uri, Future<List<SportsEvent>>> _inFlight = {};

  /// ESPN scoreboard URI for [league] covering `[fromUtc, toUtc]` (UTC).
  ///
  /// `dates` is a single `YYYYMMDD` day when both bounds fall on the same UTC
  /// date, otherwise a `YYYYMMDD-YYYYMMDD` range. Throws [ArgumentError] for
  /// leagues without an ESPN feed.
  static Uri espnScoreboardUri(
    SportsLeague league,
    DateTime fromUtc,
    DateTime toUtc,
  ) {
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
      '?dates=${_datesParameter(fromUtc, toUtc)}&limit=200',
    );
  }

  /// Events for [league] whose feed covers `[fromUtc, toUtc]`.
  ///
  /// Serves a fresh cache entry unless [force] is set, shares one in-flight
  /// fetch per URI, and falls back to the stale entry when the fetch or the
  /// JSON body fails. Throws [SportsFeedException] when nothing is cached.
  /// Returned lists are sorted by start, then id.
  Future<List<SportsEvent>> fetchLeague(
    SportsLeague league, {
    required DateTime fromUtc,
    required DateTime toUtc,
    bool force = false,
  }) async {
    final uri = _requestUri(league, fromUtc, toUtc);
    if (uri == null) return const [];
    if (!force) {
      final cached = _cache[uri];
      if (cached != null && _isFresh(cached)) {
        return _window(cached.events, league, fromUtc, toUtc);
      }
    }
    return _window(await _pendingOrStart(league, uri), league, fromUtc, toUtc);
  }

  /// The feed URI for one request, or null when the league has no feed.
  Uri? _requestUri(SportsLeague league, DateTime fromUtc, DateTime toUtc) {
    if (league.id == _f1LeagueId) return jolpicaSeasonUri;
    if (league.espnPath == null) return null;
    return espnScoreboardUri(league, fromUtc, toUtc);
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
      events = _parseBody(await _fetch(uri), uri, league);
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
    final ttl = entry.events.any(_isLive) ? liveTtl : scheduleTtl;
    return _clock().difference(entry.fetchedAt) < ttl;
  }

  static bool _isLive(SportsEvent event) =>
      event.status == SportsEventStatus.live;

  static String _datesParameter(DateTime fromUtc, DateTime toUtc) {
    final from = _compactUtcDate(fromUtc);
    if (_isSameUtcDay(fromUtc, toUtc)) return from;
    return '$from-${_compactUtcDate(toUtc)}';
  }

  static bool _isSameUtcDay(DateTime a, DateTime b) {
    final first = a.toUtc();
    final second = b.toUtc();
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
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
