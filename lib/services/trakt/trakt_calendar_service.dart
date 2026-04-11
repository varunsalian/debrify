import 'package:flutter/foundation.dart';

import '../../models/trakt/trakt_calendar_entry.dart';
import 'trakt_service.dart';

/// Chunk fetcher signature — injected for tests, defaults to the real TraktService.
typedef _ChunkFetcher = Future<List<TraktCalendarEntry>> Function(
  DateTime chunkStart,
  int days,
);

/// Service that fetches Trakt upcoming episodes in 33-day chunks and caches
/// them in memory with a 15-minute TTL.
///
/// All chunks are aligned to Monday boundaries so repeated calls for
/// overlapping date ranges hit the same cache keys deterministically.
class TraktCalendarService {
  static final TraktCalendarService instance = TraktCalendarService._(
    fetcher: _defaultFetcher,
  );

  TraktCalendarService._({required _ChunkFetcher fetcher}) : _fetcher = fetcher;

  /// Test-only constructor that injects a fake fetcher.
  @visibleForTesting
  factory TraktCalendarService.forTesting({
    required _ChunkFetcher fetcher,
  }) =>
      TraktCalendarService._(fetcher: fetcher);

  static const int _chunkDays = 33;
  static const Duration _ttl = Duration(minutes: 15);

  final _ChunkFetcher _fetcher;
  final Map<String, _CachedChunk> _chunkCache = {};

  /// Fetch or return-cached a single 33-day chunk aligned to Monday boundaries.
  ///
  /// - [chunkStart] is auto-aligned to the Monday on or before the given date.
  /// - [force] skips the cache and always refetches.
  /// - Returns `[]` and logs on error (never throws).
  Future<List<TraktCalendarEntry>> getChunk(
    DateTime chunkStart, {
    bool force = false,
  }) async {
    final aligned = _chunkStartFor(chunkStart);
    final key = _cacheKey(aligned);

    if (!force) {
      final cached = _chunkCache[key];
      if (cached != null && cached.isFresh) {
        return cached.entries;
      }
    }

    try {
      final entries = await _fetcher(aligned, _chunkDays);
      _chunkCache[key] = _CachedChunk(entries, DateTime.now());
      return entries;
    } catch (e) {
      debugPrint('TraktCalendarService: chunk fetch failed: $e');
      return [];
    }
  }

  /// Fetch the inclusive local-date range `[start, end]`, splitting into
  /// 33-day chunks as needed. Results are de-duped by
  /// `(showTraktId, season, episode)` and grouped by local midnight.
  ///
  /// Returned map keys are `DateTime(year, month, day)` in local time.
  /// Empty buckets are not included.
  Future<Map<DateTime, List<TraktCalendarEntry>>> getRange(
    DateTime start,
    DateTime end,
  ) async {
    if (end.isBefore(start)) {
      return <DateTime, List<TraktCalendarEntry>>{};
    }

    // Collect Monday-aligned chunk starts that cover [start, end]
    final chunkStarts = <DateTime>[];
    DateTime cursor = _chunkStartFor(start);
    while (!cursor.isAfter(end)) {
      chunkStarts.add(cursor);
      cursor = cursor.add(const Duration(days: _chunkDays));
    }

    // Fetch in parallel; getChunk handles cache + errors internally
    final chunkResults = await Future.wait(
      chunkStarts.map((s) => getChunk(s)),
    );

    // Flatten, de-dupe, filter to [start, end]
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    final seenKeys = <String>{};
    final filtered = <TraktCalendarEntry>[];
    for (final chunk in chunkResults) {
      for (final entry in chunk) {
        final local = entry.firstAiredLocal;
        final localDay = DateTime(local.year, local.month, local.day);
        if (localDay.isBefore(startDay) || localDay.isAfter(endDay)) continue;
        final key =
            '${entry.showTraktId}-${entry.seasonNumber}-${entry.episodeNumber}';
        if (seenKeys.add(key)) {
          filtered.add(entry);
        }
      }
    }

    // Group by local midnight
    final grouped = <DateTime, List<TraktCalendarEntry>>{};
    for (final entry in filtered) {
      final local = entry.firstAiredLocal;
      final bucket = DateTime(local.year, local.month, local.day);
      (grouped[bucket] ??= <TraktCalendarEntry>[]).add(entry);
    }
    return grouped;
  }

  /// Drop all cached chunks. Call on Trakt logout or user-triggered refresh.
  void invalidate() {
    _chunkCache.clear();
  }

  /// Walk back to the Monday on or before [date]. Strips any time component.
  static DateTime _chunkStartFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final daysSinceMonday = (day.weekday - DateTime.monday) % 7;
    return day.subtract(Duration(days: daysSinceMonday));
  }

  /// Test-only accessor for chunk alignment math.
  @visibleForTesting
  static DateTime debugChunkStartFor(DateTime date) => _chunkStartFor(date);

  /// Test-only helper to mark all cache entries as expired (for TTL tests).
  @visibleForTesting
  void debugExpireAllCacheEntries() {
    final expired = DateTime.now().subtract(_ttl + const Duration(seconds: 1));
    _chunkCache.updateAll(
      (key, chunk) => _CachedChunk(chunk.entries, expired),
    );
  }

  static String _cacheKey(DateTime aligned) =>
      '${aligned.year}-${aligned.month}-${aligned.day}';

  /// Default fetcher — calls the real TraktService and transforms the raw JSON.
  static Future<List<TraktCalendarEntry>> _defaultFetcher(
    DateTime start,
    int days,
  ) async {
    final raw = await TraktService.instance.fetchCalendarMyShows(
      startDate: start,
      days: days,
    );
    return raw
        .whereType<Map<String, dynamic>>()
        .map(TraktCalendarEntry.fromTraktJson)
        .whereType<TraktCalendarEntry>()
        .toList();
  }
}

class _CachedChunk {
  final List<TraktCalendarEntry> entries;
  final DateTime fetchedAt;
  _CachedChunk(this.entries, this.fetchedAt);

  bool get isFresh =>
      DateTime.now().difference(fetchedAt) < TraktCalendarService._ttl;
}
