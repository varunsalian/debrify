import 'package:flutter/foundation.dart';

import '../../models/trakt/trakt_calendar_entry.dart';
import 'mdblist_models.dart';
import 'mdblist_service.dart';

typedef MdblistCalendarFetcher =
    Future<MdblistResult<List<Map<String, dynamic>>>> Function(
      DateTime start,
      DateTime end,
    );
typedef MdblistShowResolver =
    Future<MdblistResult<Map<String, dynamic>>> Function(int tmdbId);

/// Profile-scoped, last-good calendar cache for MDBList episode events.
class MdblistCalendarService {
  MdblistCalendarService._({
    required MdblistCalendarFetcher fetcher,
    required MdblistShowResolver resolver,
  }) : _fetcher = fetcher,
       _resolver = resolver;

  static final MdblistCalendarService instance = MdblistCalendarService._(
    fetcher: (start, end) =>
        MdblistService.instance.fetchCalendarEvents(start: start, end: end),
    resolver: (id) => MdblistService.instance.resolveTmdb(id, 'show'),
  );

  @visibleForTesting
  factory MdblistCalendarService.forTesting({
    required MdblistCalendarFetcher fetcher,
    required MdblistShowResolver resolver,
  }) => MdblistCalendarService._(fetcher: fetcher, resolver: resolver);

  static const _ttl = Duration(minutes: 15);
  final MdblistCalendarFetcher _fetcher;
  final MdblistShowResolver _resolver;
  final Map<String, _CalendarCache> _cache = {};
  final Map<int, Map<String, dynamic>> _showCache = {};
  final Map<String, Future<Map<DateTime, List<TraktCalendarEntry>>>> _inFlight =
      {};

  Future<Map<DateTime, List<TraktCalendarEntry>>> getRange(
    DateTime start,
    DateTime end,
  ) async {
    if (end.isBefore(start) || !kMdblistEnabled) return {};
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final key = '${startDay.toIso8601String()}/${endDay.toIso8601String()}';
    final cached = _cache[key];
    if (cached != null && cached.fresh) return cached.entries;
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _load(startDay, endDay, cached?.entries);
    _inFlight[key] = future;
    try {
      final result = await future;
      if (!identical(_inFlight[key], future)) return result;
      return result;
    } finally {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
    }
  }

  @visibleForTesting
  Future<Map<DateTime, List<TraktCalendarEntry>>> debugLoadForTesting(
    DateTime start,
    DateTime end, {
    bool force = false,
  }) async {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final key = '${startDay.toIso8601String()}/${endDay.toIso8601String()}';
    final cached = _cache[key];
    if (!force && cached != null && cached.fresh) return cached.entries;
    return _load(startDay, endDay, cached?.entries);
  }

  Future<Map<DateTime, List<TraktCalendarEntry>>> _load(
    DateTime start,
    DateTime end,
    Map<DateTime, List<TraktCalendarEntry>>? lastGood,
  ) async {
    final raw = await _fetcher(start, end);
    if (!raw.isSuccess) return lastGood ?? {};

    final showIds = raw.data!
        .where((row) => row['type'] == 'episode')
        .map((row) => _integer(row['show_tmdb']))
        .whereType<int>()
        .toSet();
    final missing = showIds.where((id) => !_showCache.containsKey(id));
    for (final batch in _batches(missing.toList(), 6)) {
      final resolved = await Future.wait(batch.map(_resolver));
      for (var i = 0; i < batch.length; i++) {
        if (resolved[i].isSuccess) _showCache[batch[i]] = resolved[i].data!;
      }
    }

    final grouped = <DateTime, List<TraktCalendarEntry>>{};
    final seen = <String>{};
    for (final row in raw.data!) {
      final showId = _integer(row['show_tmdb']);
      final entry = TraktCalendarEntry.fromMdblistCalendarJson(
        row,
        resolvedShow: showId == null ? null : _showCache[showId],
      );
      if (entry == null) continue;
      final unique = '$showId-${entry.seasonNumber}-${entry.episodeNumber}';
      if (!seen.add(unique)) continue;
      final day = entry.firstAiredLocal;
      (grouped[DateTime(day.year, day.month, day.day)] ??= []).add(entry);
    }
    final key = '${start.toIso8601String()}/${end.toIso8601String()}';
    _cache[key] = _CalendarCache(grouped, DateTime.now());
    return grouped;
  }

  void invalidate() => _cache.clear();

  void resetProfileScope() {
    _cache.clear();
    _showCache.clear();
    _inFlight.clear();
  }

  static int? _integer(Object? value) => value is num
      ? value.toInt()
      : value is String
      ? int.tryParse(value)
      : null;

  static Iterable<List<T>> _batches<T>(List<T> values, int size) sync* {
    for (var i = 0; i < values.length; i += size) {
      yield values.sublist(i, (i + size).clamp(0, values.length));
    }
  }
}

class _CalendarCache {
  const _CalendarCache(this.entries, this.fetchedAt);
  final Map<DateTime, List<TraktCalendarEntry>> entries;
  final DateTime fetchedAt;
  bool get fresh =>
      DateTime.now().difference(fetchedAt) < MdblistCalendarService._ttl;
}
