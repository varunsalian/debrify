import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/trakt/trakt_calendar_entry.dart';
import 'package:debrify/services/trakt/trakt_calendar_service.dart';

void main() {
  group('TraktCalendarService.invalidate', () {
    test('clears all cached chunks', () async {
      final fetcher = _FakeFetcher();
      final service = TraktCalendarService.forTesting(fetcher: fetcher.call);

      fetcher.entries = [_fakeEntry(day: 14)];
      await service.getChunk(DateTime(2026, 4, 13));
      expect(fetcher.callCount, 1);

      service.invalidate();

      await service.getChunk(DateTime(2026, 4, 13));
      expect(fetcher.callCount, 2,
          reason: 'cache should be empty after invalidate');
    });
  });

  group('TraktCalendarService.getRange', () {
    late _FakeFetcher fetcher;
    late TraktCalendarService service;

    setUp(() {
      fetcher = _FakeFetcher();
      service = TraktCalendarService.forTesting(fetcher: fetcher.call);
    });

    test('single chunk covers requested range', () async {
      final start = DateTime(2026, 4, 13); // Monday
      final end = DateTime(2026, 4, 20);
      fetcher.entries = [
        _fakeEntry(day: 14),
        _fakeEntry(day: 17),
      ];

      final result = await service.getRange(start, end);

      expect(fetcher.callCount, 1);
      expect(result.keys.length, 2);
    });

    test('range spanning two chunks dispatches two fetches', () async {
      final start = DateTime(2026, 4, 13); // Monday
      final end = DateTime(2026, 5, 25);
      fetcher.entries = [_fakeEntry(day: 14)];

      await service.getRange(start, end);

      expect(fetcher.callCount, 2);
    });

    test('entries are grouped by local date at midnight', () async {
      final start = DateTime(2026, 4, 13);
      final end = DateTime(2026, 4, 20);
      // Both entries fall on April 14 locally (assuming local timezone
      // doesn't shift them to a different day — for tests running in
      // any common TZ, 02:00 UTC on April 14 is April 13 or 14 local).
      final e1 = _fakeEntry(day: 14);
      // Create a second entry with the SAME local date but unique identity
      final utc = DateTime.utc(2026, 4, 14, 3, 0);
      final e2 = TraktCalendarEntry(
        firstAiredUtc: utc,
        firstAiredLocal: utc.toLocal(),
        showTitle: 'Other Show',
        showYear: 2026,
        showImdbId: 'tt99999999',
        showTraktId: 9999,
        seasonNumber: 2,
        episodeNumber: 3,
        episodeTitle: 'Other Ep',
        episodeOverview: null,
        runtimeMinutes: 45,
        posterUrl: null,
      );
      fetcher.entries = [e1, e2];

      final result = await service.getRange(start, end);

      // Both entries should be in the same local-date bucket.
      // Use the actual localDate of e1 as the key.
      final local = e1.firstAiredLocal;
      final bucket = DateTime(local.year, local.month, local.day);
      expect(result[bucket]?.length, 2);
    });

    test('duplicate entries across chunks are de-duped', () async {
      final shared = _fakeEntry(day: 14);
      fetcher.nextEntries = [
        [shared],
        [shared],
      ];

      final start = DateTime(2026, 4, 13);
      final end = DateTime(2026, 5, 25);

      final result = await service.getRange(start, end);

      final local = shared.firstAiredLocal;
      final bucket = DateTime(local.year, local.month, local.day);
      expect(result[bucket]?.length, 1, reason: 'duplicate should be removed');
    });

    test('cached chunks are reused across calls', () async {
      fetcher.entries = [_fakeEntry(day: 14)];
      final start = DateTime(2026, 4, 13);
      final end = DateTime(2026, 4, 20);

      await service.getRange(start, end);
      await service.getRange(start, end);

      expect(fetcher.callCount, 1);
    });
  });

  group('TraktCalendarService.getChunk', () {
    late _FakeFetcher fetcher;
    late TraktCalendarService service;

    setUp(() {
      fetcher = _FakeFetcher();
      service = TraktCalendarService.forTesting(fetcher: fetcher.call);
    });

    test('aligns chunk start to Monday', () {
      // Wednesday, April 15, 2026
      final wed = DateTime(2026, 4, 15);
      final aligned = TraktCalendarService.debugChunkStartFor(wed);
      expect(aligned.weekday, DateTime.monday);
      expect(aligned.year, 2026);
      expect(aligned.month, 4);
      expect(aligned.day, 13); // Monday of that week
    });

    test('Monday input returns itself aligned', () {
      final mon = DateTime(2026, 4, 13); // Monday
      final aligned = TraktCalendarService.debugChunkStartFor(mon);
      expect(aligned.weekday, DateTime.monday);
      expect(aligned.day, 13);
    });

    test('Sunday input walks back 6 days', () {
      final sun = DateTime(2026, 4, 19); // Sunday
      final aligned = TraktCalendarService.debugChunkStartFor(sun);
      expect(aligned.weekday, DateTime.monday);
      expect(aligned.day, 13); // Previous Monday
    });

    test('getChunk fetches on cache miss and caches result', () async {
      final monday = DateTime(2026, 4, 13);
      fetcher.entries = [_fakeEntry(day: 15)];

      final result = await service.getChunk(monday);

      expect(result.length, 1);
      expect(fetcher.callCount, 1);
      expect(fetcher.lastStart, monday);
      expect(fetcher.lastDays, 33);
    });

    test('getChunk returns cached result on second call within TTL', () async {
      final monday = DateTime(2026, 4, 13);
      fetcher.entries = [_fakeEntry(day: 15)];

      await service.getChunk(monday);
      await service.getChunk(monday);

      expect(fetcher.callCount, 1, reason: 'second call should hit cache');
    });

    test('non-Monday date uses aligned cache key', () async {
      final monday = DateTime(2026, 4, 13);
      final wed = DateTime(2026, 4, 15);
      fetcher.entries = [_fakeEntry(day: 15)];

      await service.getChunk(monday);
      await service.getChunk(wed); // should hit same cache entry

      expect(fetcher.callCount, 1);
    });

    test('force=true bypasses cache', () async {
      final monday = DateTime(2026, 4, 13);
      fetcher.entries = [_fakeEntry(day: 15)];

      await service.getChunk(monday);
      await service.getChunk(monday, force: true);

      expect(fetcher.callCount, 2);
    });

    test('expired cache entry triggers refetch', () async {
      final monday = DateTime(2026, 4, 13);
      fetcher.entries = [_fakeEntry(day: 15)];

      await service.getChunk(monday);
      service.debugExpireAllCacheEntries();
      await service.getChunk(monday);

      expect(fetcher.callCount, 2);
    });

    test('fetcher exception returns empty list and does not cache', () async {
      final monday = DateTime(2026, 4, 13);
      fetcher.shouldThrow = true;

      final result = await service.getChunk(monday);

      expect(result, isEmpty);

      // Next call should retry (nothing cached)
      fetcher.shouldThrow = false;
      fetcher.entries = [_fakeEntry(day: 15)];
      final second = await service.getChunk(monday);
      expect(second.length, 1);
      expect(fetcher.callCount, 2);
    });
  });
}

/// Fake fetcher injected into TraktCalendarService for testing.
class _FakeFetcher {
  List<TraktCalendarEntry> entries = [];
  List<List<TraktCalendarEntry>>? nextEntries;
  int callCount = 0;
  DateTime? lastStart;
  int? lastDays;
  bool shouldThrow = false;

  Future<List<TraktCalendarEntry>> call(DateTime start, int days) async {
    final idx = callCount;
    callCount++;
    lastStart = start;
    lastDays = days;
    if (shouldThrow) throw Exception('fake network failure');
    if (nextEntries != null && idx < nextEntries!.length) {
      return nextEntries![idx];
    }
    return entries;
  }
}

/// Build a minimal calendar entry for testing.
TraktCalendarEntry _fakeEntry({required int day}) {
  final utc = DateTime.utc(2026, 4, day, 2, 0);
  return TraktCalendarEntry(
    firstAiredUtc: utc,
    firstAiredLocal: utc.toLocal(),
    showTitle: 'Show $day',
    showYear: 2026,
    showImdbId: 'tt000000$day',
    showTraktId: day,
    seasonNumber: 1,
    episodeNumber: day,
    episodeTitle: 'Ep $day',
    episodeOverview: null,
    runtimeMinutes: 45,
    posterUrl: null,
  );
}
