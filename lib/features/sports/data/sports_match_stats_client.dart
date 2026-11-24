// Fetches and caches one match's ESPN summary for the stats page.
//
// Data layer: HTTP only through the injected [SportsFetch], time only from the
// injected clock, so tests run offline on fake time. Summaries are large
// (100–900 KB) and public, so the cache is device-wide, small (a few recently
// opened matches) and short-lived: a live match goes stale within seconds,
// a finished one keeps for half an hour. Concurrent loads of one match share
// a request, and a failed refresh falls back to the last good copy (a live
// one only while it is a few minutes old).
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

import 'espn_summary_parser.dart';
import 'sports_feed_client.dart' show SportsFeedException, SportsFetch;

/// Whether the stats page can show [league]: ESPN-backed two-team leagues.
/// Cricket, tennis, fights, golf and racing summaries have other shapes.
bool sportsMatchStatsSupported(SportsLeague? league) =>
    league != null &&
    league.espnPath != null &&
    league.discoverSport == null &&
    sportsEventShapeOf(league) == SportsEventShape.teams;

class _Entry {
  const _Entry(this.stats, this.fetchedAt);

  final SportsMatchStats stats;
  final DateTime fetchedAt;
}

class SportsMatchStatsClient {
  SportsMatchStatsClient({
    required SportsFetch fetch,
    DateTime Function()? clock,
    this.maxEntries = 8,
  }) : _fetch = fetch,
       _clock = clock ?? DateTime.now;

  static const String _espnBase =
      'https://site.api.espn.com/apis/site/v2/sports';

  /// Bodies longer than this parse in [Isolate.run].
  static const int isolateParseThreshold = 64 * 1024;

  static const Duration liveTtl = Duration(seconds: 20);
  static const Duration scheduledTtl = Duration(minutes: 5);
  static const Duration settledTtl = Duration(minutes: 30);

  /// How old a live copy may be and still stand in for a failed fetch.
  static const Duration liveFallbackLimit = Duration(minutes: 5);

  final SportsFetch _fetch;
  final DateTime Function() _clock;
  final int maxEntries;

  /// Insertion-ordered; re-inserted on every store, so the first key is the
  /// least recently fetched.
  final LinkedHashMap<SportsMatchKey, _Entry> _cache = LinkedHashMap();
  final Map<SportsMatchKey, Future<SportsMatchStats>> _inFlight = {};

  /// The summary URL for [key], or null when its league has no stats page.
  static Uri? summaryUri(SportsMatchKey key) {
    final league = sportsLeagueById(key.leagueId);
    if (!sportsMatchStatsSupported(league)) return null;
    return Uri.parse(
      '$_espnBase/${league!.espnPath}/summary',
    ).replace(queryParameters: {'event': key.eventId});
  }

  /// The match's stats, from the cache while it is fresh.
  ///
  /// Throws [SportsFeedException] when the league is unsupported, or when
  /// the fetch fails with no earlier copy to fall back to.
  Future<SportsMatchStats> load(SportsMatchKey key) {
    final cached = _cache[key];
    if (cached != null && _isFresh(cached)) {
      return Future.value(cached.stats);
    }
    // A block body on purpose: `=> _inFlight.remove(key)` would hand
    // whenComplete this very future to wait for, and it never completes.
    return _inFlight[key] ??= _load(key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<SportsMatchStats> _load(SportsMatchKey key) async {
    final uri = summaryUri(key);
    if (uri == null) {
      throw SportsFeedException(
        Uri(path: key.leagueId),
        'no stats feed for league ${key.leagueId}',
      );
    }
    Exception failure;
    try {
      final stats = await _parse(await _fetch(uri), uri);
      _cache
        ..remove(key)
        ..[key] = _Entry(stats, _clock());
      while (_cache.length > maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      return stats;
    } on Exception catch (error) {
      // Transport and format failures only. An Error (a parser bug on a
      // changed feed shape) propagates with its own stack trace rather than
      // hiding behind an old copy.
      failure = error;
    }
    final stale = _cache[key];
    if (stale != null && _usableWhenOffline(stale)) return stale.stats;
    if (failure is SportsFeedException) throw failure;
    throw SportsFeedException(uri, '$failure');
  }

  Future<SportsMatchStats> _parse(String body, Uri uri) async {
    final SportsMatchStats? stats;
    try {
      stats = body.length > isolateParseThreshold
          ? await Isolate.run(() => parseEspnSummary(jsonDecode(body)))
          : parseEspnSummary(jsonDecode(body));
    } on FormatException catch (error) {
      throw SportsFeedException(uri, 'body was not JSON: ${error.message}');
    }
    if (stats == null) {
      throw SportsFeedException(uri, 'summary did not describe a match');
    }
    return stats;
  }

  bool _isFresh(_Entry entry) {
    final stats = entry.stats;
    final now = _clock();
    // A preview is stale once kick-off arrives, however recently it was
    // fetched: the match may be live by now.
    final start = stats.start;
    if (!stats.started && start != null && !now.isBefore(start)) return false;
    final ttl = switch (stats.status) {
      SportsEventStatus.live => liveTtl,
      SportsEventStatus.scheduled => scheduledTtl,
      SportsEventStatus.finished || SportsEventStatus.postponed => settledTtl,
    };
    return now.difference(entry.fetchedAt) < ttl;
  }

  /// A failed fetch may fall back to [entry] unless it is a live match
  /// fetched long enough ago that showing it as current would mislead.
  bool _usableWhenOffline(_Entry entry) =>
      entry.stats.status != SportsEventStatus.live ||
      _clock().difference(entry.fetchedAt) < liveFallbackLimit;
}
