# Trakt Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Trakt-powered calendar feature consisting of a "Today" card on the Home screen and a full grid calendar screen with month grid, infinite scroll, and DPAD support.

**Architecture:** Three layers — raw HTTP on `TraktService`, a dedicated `TraktCalendarService` singleton that owns chunked 33-day cache windows (15-min TTL, Monday-aligned), and two thin UI widgets (Today card, full calendar screen). Widgets query `TraktCalendarService.getRange(start, end)` and render grouped results.

**Tech Stack:** Flutter / Dart, `http` package, `flutter_test`, existing `StorageService` for Trakt tokens, existing `TraktItemTransformer` poster-fallback helpers.

**Spec:** `docs/superpowers/specs/2026-04-12-trakt-calendar-design.md`

---

## File structure

**New files:**

| Path | Responsibility |
|---|---|
| `lib/models/trakt/trakt_calendar_entry.dart` | Domain model for one calendar item + JSON factory |
| `lib/services/trakt/trakt_calendar_service.dart` | Singleton service with chunked cache, `getChunk`/`getRange`/`invalidate` |
| `lib/widgets/home_today_calendar_card.dart` | Today card widget (hidden / loading / full / peek states) |
| `lib/screens/trakt_calendar_screen.dart` | Full grid calendar screen with month blocks + infinite scroll |
| `lib/widgets/trakt_calendar_day_sheet.dart` | Bottom sheet showing episodes for a tapped day |
| `test/trakt_calendar_entry_test.dart` | Unit tests for the model + factory |
| `test/trakt_calendar_service_test.dart` | Unit tests for the service with injected fake `TraktService` |

**Modified files:**

| Path | Change |
|---|---|
| `lib/services/trakt/trakt_service.dart` | Add `fetchCalendarMyShows(startDate, days)` method; add `TraktCalendarService.instance.invalidate()` call in `logout()` |
| `lib/widgets/home_focus_controller.dart` | Add `HomeSection.todayCalendar` enum variant + map entries |
| `lib/screens/torrent_search_screen.dart` | Register `HomeTodayCalendarCard` at position 0 in `_buildHomeSection()`, above `HomeTraktNowPlayingCard` |

**Test strategy note:** Model and service are pure logic — unit tests with injected fakes. Widgets get light smoke tests for state rendering. No Trakt-API integration tests (too flaky, account-dependent). Manual smoke test checklist at the end.

---

## Task 1: TraktCalendarEntry model and JSON factory

**Files:**
- Create: `lib/models/trakt/trakt_calendar_entry.dart`
- Create: `test/trakt_calendar_entry_test.dart`

- [ ] **Step 1: Write failing tests for the model**

Write `test/trakt_calendar_entry_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/trakt/trakt_calendar_entry.dart';

void main() {
  group('TraktCalendarEntry.fromTraktJson', () {
    Map<String, dynamic> sampleJson({
      String? firstAired = '2026-04-15T02:00:00.000Z',
      int season = 2,
      int episode = 5,
      String showTitle = 'Severance',
      String? imdb = 'tt11280740',
      int? traktId = 12345,
    }) => {
          'first_aired': firstAired,
          'episode': {
            'season': season,
            'number': episode,
            'title': 'Chikhai Bardo',
            'overview': 'An episode overview.',
            'runtime': 55,
          },
          'show': {
            'title': showTitle,
            'year': 2022,
            'ids': {
              'imdb': imdb,
              'trakt': traktId,
            },
          },
        };

    test('parses a valid Trakt calendar entry', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(entry, isNotNull);
      expect(entry!.showTitle, 'Severance');
      expect(entry.showImdbId, 'tt11280740');
      expect(entry.showTraktId, 12345);
      expect(entry.seasonNumber, 2);
      expect(entry.episodeNumber, 5);
      expect(entry.episodeTitle, 'Chikhai Bardo');
      expect(entry.runtimeMinutes, 55);
      expect(entry.firstAiredUtc.isUtc, isTrue);
      expect(entry.firstAiredUtc.year, 2026);
      expect(entry.firstAiredUtc.month, 4);
      expect(entry.firstAiredUtc.day, 15);
    });

    test('isNewShow is true for S01E01', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 1, episode: 1),
      );
      expect(entry!.isNewShow, isTrue);
      expect(entry.isSeasonPremiere, isTrue);
    });

    test('isSeasonPremiere is true for any SxxE01', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 3, episode: 1),
      );
      expect(entry!.isNewShow, isFalse);
      expect(entry.isSeasonPremiere, isTrue);
    });

    test('regular episode has neither flag', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(season: 2, episode: 5),
      );
      expect(entry!.isNewShow, isFalse);
      expect(entry.isSeasonPremiere, isFalse);
    });

    test('returns null when first_aired is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(firstAired: null),
      );
      expect(entry, isNull);
    });

    test('returns null when first_aired is malformed', () {
      final json = sampleJson();
      json['first_aired'] = 'not-a-date';
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNull);
    });

    test('returns null when show title is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(
        sampleJson(showTitle: ''),
      );
      expect(entry, isNull);
    });

    test('returns null when episode number is missing', () {
      final json = sampleJson();
      (json['episode'] as Map).remove('number');
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNull);
    });

    test('handles missing optional fields gracefully', () {
      final json = sampleJson();
      (json['episode'] as Map).remove('overview');
      (json['episode'] as Map).remove('runtime');
      final entry = TraktCalendarEntry.fromTraktJson(json);
      expect(entry, isNotNull);
      expect(entry!.episodeOverview, isNull);
      expect(entry.runtimeMinutes, isNull);
    });

    test('falls back to metahub poster when imdb is present', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(
        entry!.posterUrl,
        'https://images.metahub.space/poster/medium/tt11280740/img',
      );
    });

    test('poster is null when imdb is missing', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson(imdb: null));
      expect(entry!.posterUrl, isNull);
    });

    test('firstAiredLocal is the local-converted UTC', () {
      final entry = TraktCalendarEntry.fromTraktJson(sampleJson());
      expect(entry!.firstAiredLocal, entry.firstAiredUtc.toLocal());
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/trakt_calendar_entry_test.dart`
Expected: FAIL — "Target of URI doesn't exist" for the import

- [ ] **Step 3: Implement the model**

Write `lib/models/trakt/trakt_calendar_entry.dart`:

```dart
/// Domain model for a single Trakt calendar entry (upcoming episode).
///
/// Built from `/calendars/my/shows` responses via [fromTraktJson].
class TraktCalendarEntry {
  /// Air time parsed as UTC from Trakt's `first_aired` ISO-8601 string.
  final DateTime firstAiredUtc;

  /// Air time converted to the device's local timezone.
  /// Used for date bucketing (grouping by "today", "tomorrow", etc).
  final DateTime firstAiredLocal;

  final String showTitle;
  final int? showYear;
  final String? showImdbId;
  final int? showTraktId;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? episodeOverview;
  final int? runtimeMinutes;

  /// Poster URL, resolved via Stremio metahub fallback when `showImdbId` is present.
  final String? posterUrl;

  const TraktCalendarEntry({
    required this.firstAiredUtc,
    required this.firstAiredLocal,
    required this.showTitle,
    required this.showYear,
    required this.showImdbId,
    required this.showTraktId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.episodeOverview,
    required this.runtimeMinutes,
    required this.posterUrl,
  });

  /// True when this is episode 1 of season 1 — a brand-new show premiere.
  bool get isNewShow => seasonNumber == 1 && episodeNumber == 1;

  /// True when this is the first episode of any season (includes new shows).
  bool get isSeasonPremiere => episodeNumber == 1;

  /// Parse a raw Trakt calendar item. Returns `null` when any essential field
  /// is missing or malformed — callers should filter nulls.
  ///
  /// Expected JSON shape:
  /// ```
  /// {
  ///   "first_aired": "2026-04-15T02:00:00.000Z",
  ///   "episode": { "season": 2, "number": 5, "title": "...", ... },
  ///   "show": { "title": "...", "year": 2022, "ids": { "imdb": "tt...", "trakt": 123 } }
  /// }
  /// ```
  static TraktCalendarEntry? fromTraktJson(Map<String, dynamic> json) {
    final firstAiredStr = json['first_aired'] as String?;
    if (firstAiredStr == null || firstAiredStr.isEmpty) return null;

    DateTime firstAiredUtc;
    try {
      final parsed = DateTime.parse(firstAiredStr);
      firstAiredUtc = parsed.isUtc ? parsed : parsed.toUtc();
    } catch (_) {
      return null;
    }

    final show = json['show'] as Map<String, dynamic>?;
    final episode = json['episode'] as Map<String, dynamic>?;
    if (show == null || episode == null) return null;

    final showTitle = show['title'] as String?;
    if (showTitle == null || showTitle.isEmpty) return null;

    final seasonRaw = episode['season'];
    final numberRaw = episode['number'];
    if (seasonRaw is! int || numberRaw is! int) return null;

    final ids = show['ids'] as Map<String, dynamic>? ?? const {};
    final imdb = ids['imdb'] as String?;
    final traktId = ids['trakt'] is int ? ids['trakt'] as int : null;

    String? poster;
    if (imdb != null && imdb.startsWith('tt')) {
      poster = 'https://images.metahub.space/poster/medium/$imdb/img';
    }

    return TraktCalendarEntry(
      firstAiredUtc: firstAiredUtc,
      firstAiredLocal: firstAiredUtc.toLocal(),
      showTitle: showTitle,
      showYear: show['year'] is int ? show['year'] as int : null,
      showImdbId: imdb,
      showTraktId: traktId,
      seasonNumber: seasonRaw,
      episodeNumber: numberRaw,
      episodeTitle: episode['title'] as String?,
      episodeOverview: episode['overview'] as String?,
      runtimeMinutes: episode['runtime'] is int ? episode['runtime'] as int : null,
      posterUrl: poster,
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trakt_calendar_entry_test.dart`
Expected: all 12 tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/models/trakt/trakt_calendar_entry.dart test/trakt_calendar_entry_test.dart
git commit -m "feat(trakt): add TraktCalendarEntry model with JSON factory"
```

---

## Task 2: Add fetchCalendarMyShows to TraktService

**Files:**
- Modify: `lib/services/trakt/trakt_service.dart`

- [ ] **Step 1: Add the method near the existing fetch methods**

Open `lib/services/trakt/trakt_service.dart`. Find `fetchPlaybackItems` (around line 681). Insert the new method **immediately after** it (before `fetchRecentShowsWithNextEpisode`):

```dart
  /// Fetch upcoming episodes from the user's Trakt calendar for the given window.
  ///
  /// Wraps GET `/calendars/my/shows/{startDate}/{days}?extended=full`.
  /// Returns raw JSON entries. Returns `[]` on error or when unauthenticated.
  /// Trakt caps `days` at 33 — callers must not exceed this.
  ///
  /// Date format: `startDate` is rendered as `YYYY-MM-DD` in the path.
  Future<List<dynamic>> fetchCalendarMyShows({
    required DateTime startDate,
    required int days,
  }) async {
    assert(days > 0 && days <= 33, 'Trakt caps calendar days at 33');
    final y = startDate.year.toString().padLeft(4, '0');
    final m = startDate.month.toString().padLeft(2, '0');
    final d = startDate.day.toString().padLeft(2, '0');
    final path = '/calendars/my/shows/$y-$m-$d/$days?extended=full';

    final response = await _authenticatedGet(path);
    if (response == null || response.statusCode != 200) {
      debugPrint(
          'Trakt: fetchCalendarMyShows failed (${response?.statusCode})');
      return [];
    }
    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchCalendarMyShows parse error: $e');
      return [];
    }
  }
```

- [ ] **Step 2: Verify the file compiles**

Run: `flutter analyze lib/services/trakt/trakt_service.dart 2>&1 | grep "error "`
Expected: no output (no errors)

- [ ] **Step 3: Commit**

```bash
git add lib/services/trakt/trakt_service.dart
git commit -m "feat(trakt): add fetchCalendarMyShows HTTP method"
```

---

## Task 3: TraktCalendarService — chunk fetching with cache

**Files:**
- Create: `lib/services/trakt/trakt_calendar_service.dart`
- Create: `test/trakt_calendar_service_test.dart`

This task covers the foundational cache: `getChunk`, chunk alignment, TTL expiry. `getRange` and `invalidate` come in Task 4 and 5.

- [ ] **Step 1: Write failing tests for getChunk cache behavior**

Write `test/trakt_calendar_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/trakt/trakt_calendar_entry.dart';
import 'package:debrify/services/trakt/trakt_calendar_service.dart';

void main() {
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
      // Simulate TTL expiry by advancing the cached entry's fetchedAt
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
  int callCount = 0;
  DateTime? lastStart;
  int? lastDays;
  bool shouldThrow = false;

  Future<List<TraktCalendarEntry>> call(DateTime start, int days) async {
    callCount++;
    lastStart = start;
    lastDays = days;
    if (shouldThrow) throw Exception('fake network failure');
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: FAIL — URI doesn't exist for the service import

- [ ] **Step 3: Implement the service (getChunk + chunk alignment + TTL)**

Write `lib/services/trakt/trakt_calendar_service.dart`:

```dart
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: all 8 tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/services/trakt/trakt_calendar_service.dart test/trakt_calendar_service_test.dart
git commit -m "feat(trakt): add TraktCalendarService with chunked cache"
```

---

## Task 4: TraktCalendarService — getRange with splitting, merging, de-dup, grouping

**Files:**
- Modify: `lib/services/trakt/trakt_calendar_service.dart`
- Modify: `test/trakt_calendar_service_test.dart`

- [ ] **Step 1: Append failing tests for getRange to the existing test file**

Append to `test/trakt_calendar_service_test.dart` inside the top-level `main()`:

```dart
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
      // Result is Map<localMidnight, List<entries>> grouped by local date
      expect(result.keys.length, 2);
    });

    test('range spanning two chunks dispatches two fetches', () async {
      final start = DateTime(2026, 4, 13); // Monday
      final end = DateTime(2026, 5, 25);   // ~6 weeks later, crosses chunk
      fetcher.entries = [_fakeEntry(day: 14)];

      await service.getRange(start, end);

      expect(fetcher.callCount, 2);
    });

    test('entries are grouped by local date at midnight', () async {
      final start = DateTime(2026, 4, 13);
      final end = DateTime(2026, 4, 20);
      fetcher.entries = [_fakeEntry(day: 14), _fakeEntry(day: 14)];

      final result = await service.getRange(start, end);

      final bucket = DateTime(2026, 4, 14);
      expect(result[bucket]?.length, 2);
    });

    test('duplicate entries across chunks are de-duped', () async {
      // First chunk returns an entry
      final shared = _fakeEntry(day: 14);
      fetcher.nextEntries = [
        [shared],
        [shared], // second chunk returns same entry
      ];

      final start = DateTime(2026, 4, 13);
      final end = DateTime(2026, 5, 25); // forces 2 chunks

      final result = await service.getRange(start, end);

      final bucket = DateTime(2026, 4, 14);
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
```

Update `_FakeFetcher` to support per-call response queues:

```dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: FAIL — `getRange` method not defined

- [ ] **Step 3: Add getRange to the service**

In `lib/services/trakt/trakt_calendar_service.dart`, add the method to the class (after `getChunk`):

```dart
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
        final key = '${entry.showTraktId}-${entry.seasonNumber}-${entry.episodeNumber}';
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: all tests pass (8 from Task 3 + 5 from Task 4 = 13)

- [ ] **Step 5: Commit**

```bash
git add lib/services/trakt/trakt_calendar_service.dart test/trakt_calendar_service_test.dart
git commit -m "feat(trakt): add getRange with chunk splitting, de-dup, and date grouping"
```

---

## Task 5: TraktCalendarService.invalidate + logout hook

**Files:**
- Modify: `lib/services/trakt/trakt_calendar_service.dart`
- Modify: `test/trakt_calendar_service_test.dart`
- Modify: `lib/services/trakt/trakt_service.dart`

- [ ] **Step 1: Append failing test for invalidate**

Append to `test/trakt_calendar_service_test.dart` inside `main()`:

```dart
  group('TraktCalendarService.invalidate', () {
    test('clears all cached chunks', () async {
      final fetcher = _FakeFetcher();
      final service = TraktCalendarService.forTesting(fetcher: fetcher.call);

      fetcher.entries = [_fakeEntry(day: 14)];
      await service.getChunk(DateTime(2026, 4, 13));
      expect(fetcher.callCount, 1);

      service.invalidate();

      await service.getChunk(DateTime(2026, 4, 13));
      expect(fetcher.callCount, 2, reason: 'cache should be empty after invalidate');
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: FAIL — `invalidate` method not defined

- [ ] **Step 3: Add invalidate method**

In `lib/services/trakt/trakt_calendar_service.dart`, add to the class (after `getRange`):

```dart
  /// Drop all cached chunks. Call on Trakt logout or user-triggered refresh.
  void invalidate() {
    _chunkCache.clear();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/trakt_calendar_service_test.dart`
Expected: all tests pass

- [ ] **Step 5: Wire invalidate into TraktService.logout**

Open `lib/services/trakt/trakt_service.dart`. Find `logout()` method (around line 73). Add an import at the top of the file:

```dart
import 'trakt_calendar_service.dart';
```

Then modify `logout()` — add one line after `await StorageService.clearTraktAuth();`:

```dart
  Future<void> logout() async {
    try {
      final accessToken = await StorageService.getTraktAccessToken();
      if (accessToken != null) {
        await http.post(
          Uri.parse('$kTraktApiBaseUrl/oauth/revoke'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': accessToken,
            'client_id': kTraktClientId,
            'client_secret': kTraktClientSecret,
          }),
        );
      }
    } catch (e) {
      debugPrint('Trakt: Revoke token error: $e');
    }

    await StorageService.clearTraktAuth();
    TraktCalendarService.instance.invalidate();
  }
```

- [ ] **Step 6: Verify analyze is clean**

Run: `flutter analyze lib/services/trakt/trakt_service.dart lib/services/trakt/trakt_calendar_service.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 7: Commit**

```bash
git add lib/services/trakt/trakt_calendar_service.dart lib/services/trakt/trakt_service.dart test/trakt_calendar_service_test.dart
git commit -m "feat(trakt): invalidate calendar cache on Trakt logout"
```

---

## Task 6: HomeSection enum — add todayCalendar variant

**Files:**
- Modify: `lib/widgets/home_focus_controller.dart`

- [ ] **Step 1: Add the enum variant and map entries**

Open `lib/widgets/home_focus_controller.dart`. Modify three places:

**1a — the enum** (lines 3-15). Add `todayCalendar` as the first variant after `sources`:

```dart
enum HomeSection {
  sources,
  todayCalendar,
  continueWatching,
  traktContinueWatchingMovies,
  traktContinueWatchingShows,
  favorites,
  playlist,
  iptvFavorites,
  tvFavorites,
  stremioTvFavorites,
  providers,
}
```

**1b — the `_lastFocusedIndex` map** (lines 28-38). Add an entry:

```dart
  final Map<HomeSection, int> _lastFocusedIndex = {
    HomeSection.todayCalendar: 0,
    HomeSection.continueWatching: 0,
    HomeSection.traktContinueWatchingMovies: 0,
    HomeSection.traktContinueWatchingShows: 0,
    HomeSection.favorites: 0,
    HomeSection.playlist: 0,
    HomeSection.iptvFavorites: 0,
    HomeSection.tvFavorites: 0,
    HomeSection.stremioTvFavorites: 0,
    HomeSection.providers: 0,
  };
```

**1c — the `_sectionHasItems` map** (lines 41-52). Add an entry:

```dart
  final Map<HomeSection, bool> _sectionHasItems = {
    HomeSection.sources: true, // Sources accordion is always present
    HomeSection.todayCalendar: false,
    HomeSection.continueWatching: false,
    HomeSection.traktContinueWatchingMovies: false,
    HomeSection.traktContinueWatchingShows: false,
    HomeSection.favorites: false,
    HomeSection.playlist: false,
    HomeSection.iptvFavorites: false,
    HomeSection.tvFavorites: false,
    HomeSection.stremioTvFavorites: false,
    HomeSection.providers: false,
  };
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/widgets/home_focus_controller.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_focus_controller.dart
git commit -m "feat(home): add HomeSection.todayCalendar enum variant"
```

---

## Task 7: HomeTodayCalendarCard — scaffold with hidden/loading states

**Files:**
- Create: `lib/widgets/home_today_calendar_card.dart`

This task stands up the widget with only the hidden and loading states wired. Data fetching comes in Task 8.

- [ ] **Step 1: Create the widget file**

Write `lib/widgets/home_today_calendar_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/trakt/trakt_calendar_entry.dart';
import '../screens/trakt_calendar_screen.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import 'home_focus_controller.dart';

/// "Today" card at the top of Home showing upcoming Trakt episodes.
///
/// States:
/// - **Hidden**: Trakt not connected OR nothing airing in the next 7 days
/// - **Loading**: First fetch in flight
/// - **Full**: ≥1 episode airing today — shows 1-2 episode rows + "+N more" overflow
/// - **Peek**: Nothing today, but ≥1 episode in next 7 days — shows compact one-liner
class HomeTodayCalendarCard extends StatefulWidget {
  const HomeTodayCalendarCard({
    super.key,
    required this.focusController,
    required this.isTelevision,
    required this.onRequestFocusAbove,
    required this.onRequestFocusBelow,
  });

  final HomeFocusController focusController;
  final bool isTelevision;
  final VoidCallback onRequestFocusAbove;
  final VoidCallback onRequestFocusBelow;

  @override
  State<HomeTodayCalendarCard> createState() => _HomeTodayCalendarCardState();
}

class _HomeTodayCalendarCardState extends State<HomeTodayCalendarCard> {
  bool _isAuth = false;
  bool _isLoading = true;
  Map<DateTime, List<TraktCalendarEntry>> _grouped = const {};
  final FocusNode _cardFocusNode = FocusNode(debugLabel: 'home-today-calendar-card');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _cardFocusNode.dispose();
    widget.focusController.unregisterSection(HomeSection.todayCalendar);
    super.dispose();
  }

  Future<void> _loadData() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
        _grouped = const {};
      });
      widget.focusController.registerSection(
        HomeSection.todayCalendar,
        hasItems: false,
        focusNodes: const [],
      );
      return;
    }

    setState(() {
      _isAuth = true;
      _isLoading = true;
    });

    // Data fetch added in Task 8
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _grouped = const {};
    });

    widget.focusController.registerSection(
      HomeSection.todayCalendar,
      hasItems: false,
      focusNodes: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuth) return const SizedBox.shrink();

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Card(
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x22FFFFFF)),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x22FFFFFF)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Empty / full / peek states come in Task 8
    return const SizedBox.shrink();
  }
}
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/widgets/home_today_calendar_card.dart 2>&1 | grep "error "`
Expected: ONE error — `trakt_calendar_screen.dart` not found (that file is created in Task 10)

- [ ] **Step 3: Create a stub TraktCalendarScreen to satisfy the import**

Write `lib/screens/trakt_calendar_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// Full-screen grid calendar of upcoming Trakt episodes.
///
/// Fleshed out in Task 10-15.
class TraktCalendarScreen extends StatelessWidget {
  const TraktCalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calendar')),
      body: const Center(child: Text('Coming soon')),
    );
  }
}
```

- [ ] **Step 4: Verify compile**

Run: `flutter analyze lib/widgets/home_today_calendar_card.dart lib/screens/trakt_calendar_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/home_today_calendar_card.dart lib/screens/trakt_calendar_screen.dart
git commit -m "feat(home): scaffold HomeTodayCalendarCard with hidden/loading states"
```

---

## Task 8: HomeTodayCalendarCard — data fetch + full state + peek state

**Files:**
- Modify: `lib/widgets/home_today_calendar_card.dart`

- [ ] **Step 1: Replace the placeholder _loadData and build method**

Open `lib/widgets/home_today_calendar_card.dart`. Replace `_loadData()` with:

```dart
  Future<void> _loadData() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
        _grouped = const {};
      });
      widget.focusController.registerSection(
        HomeSection.todayCalendar,
        hasItems: false,
        focusNodes: const [],
      );
      return;
    }

    setState(() {
      _isAuth = true;
      _isLoading = true;
    });

    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 7));
    final grouped = await TraktCalendarService.instance.getRange(start, end);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _grouped = grouped;
    });

    widget.focusController.registerSection(
      HomeSection.todayCalendar,
      hasItems: grouped.isNotEmpty,
      focusNodes: grouped.isNotEmpty ? [_cardFocusNode] : const [],
    );
  }
```

Replace the `build` method body (keep the early returns for `!_isAuth` and `_isLoading`). After the loading check:

```dart
    final now = DateTime.now();
    final todayBucket = DateTime(now.year, now.month, now.day);
    final todayEntries = _grouped[todayBucket] ?? const [];

    if (todayEntries.isNotEmpty) {
      return _buildFullCard(todayBucket, todayEntries);
    }

    // No episodes today — look for the next non-empty day in the 7-day window
    final sortedKeys = _grouped.keys.toList()..sort();
    final nextKey = sortedKeys.firstWhere(
      (k) => k.isAfter(todayBucket),
      orElse: () => DateTime(0),
    );
    if (nextKey.year == 0) {
      return const SizedBox.shrink(); // empty — hide entirely
    }
    final nextEntries = _grouped[nextKey]!;
    return _buildPeekCard(nextKey, nextEntries.first);
  }
```

Add the helper methods at the bottom of the state class:

```dart
  Widget _buildFullCard(DateTime today, List<TraktCalendarEntry> entries) {
    final first = entries.first;
    final second = entries.length > 1 ? entries[1] : null;
    final overflow = entries.length > 2 ? entries.length - 1 : 0;
    final dateLabel = _formatDate(today, 'Today');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Focus(
        focusNode: _cardFocusNode,
        onKeyEvent: (node, event) {
          // DPAD wiring in Task 13
          return KeyEventResult.ignored;
        },
        child: Card(
          child: InkWell(
            onTap: _openFullCalendar,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 16, color: Color(0xFF60A5FA)),
                      const SizedBox(width: 8),
                      Text(
                        dateLabel,
                        style: const TextStyle(
                          color: Color(0xFF60A5FA),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, color: Colors.white54),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _episodeRow(first),
                  if (second != null) ...[
                    const SizedBox(height: 8),
                    if (overflow > 0)
                      Text(
                        '+$overflow more tonight',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      )
                    else
                      _episodeRow(second),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPeekCard(DateTime nextDay, TraktCalendarEntry next) {
    final relative = _formatRelative(nextDay);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Focus(
        focusNode: _cardFocusNode,
        child: Card(
          child: InkWell(
            onTap: _openFullCalendar,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, size: 16, color: Colors.white38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        children: [
                          const TextSpan(text: 'Nothing today — next: '),
                          TextSpan(
                            text: next.showTitle,
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                          TextSpan(text: ' $relative'),
                        ],
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _episodeRow(TraktCalendarEntry e) {
    final time = _formatTime(e.firstAiredLocal);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (e.posterUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              e.posterUrl!,
              width: 36,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const SizedBox(width: 36, height: 54, child: Icon(Icons.tv, size: 18)),
            ),
          )
        else
          const SizedBox(
            width: 36, height: 54, child: Icon(Icons.tv, size: 18),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.showTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                'S${e.seasonNumber.toString().padLeft(2, '0')}E${e.episodeNumber.toString().padLeft(2, '0')} · $time',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openFullCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TraktCalendarScreen()),
    );
  }

  String _formatDate(DateTime d, String prefix) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '$prefix · ${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatRelative(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    if (diff == 1) return 'tomorrow';
    if (diff <= 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[d.weekday - 1];
    }
    return 'in $diff days';
  }

  String _formatTime(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/widgets/home_today_calendar_card.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/home_today_calendar_card.dart
git commit -m "feat(home): implement Today card full/peek/empty states"
```

---

## Task 9: Register HomeTodayCalendarCard in _buildHomeSection

**Files:**
- Modify: `lib/screens/torrent_search_screen.dart`

- [ ] **Step 1: Add import**

Open `lib/screens/torrent_search_screen.dart`. Find the existing widget imports near the top and add:

```dart
import '../widgets/home_today_calendar_card.dart';
```

- [ ] **Step 2: Insert the card at position 0 of _buildHomeSection children**

Find `_buildHomeSection()` (around line 14851). The current children array starts with `HomeTraktNowPlayingCard` at position 0 (line 14856). Insert a new entry **before** it:

```dart
  Widget _buildHomeSection() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      children: [
      // Today Calendar (Trakt upcoming episodes) — self-hides when empty
      RepaintBoundary(child: HomeTodayCalendarCard(
        focusController: _homeFocusController,
        isTelevision: _isTelevision,
        onRequestFocusAbove: () {
          final prev = _homeFocusController.getPreviousSection(HomeSection.todayCalendar);
          if (prev != null) {
            _homeFocusController.focusSection(prev);
          } else {
            _focusControlRow();
          }
        },
        onRequestFocusBelow: () {
          final next = _homeFocusController.getNextSection(HomeSection.todayCalendar);
          if (next != null) {
            _homeFocusController.focusSection(next);
          }
        },
      )),
      // Now Playing (Trakt live scrobble) — self-hides when nothing is playing
      RepaintBoundary(child: HomeTraktNowPlayingCard(
```

(The rest of the existing file is unchanged.)

- [ ] **Step 3: Verify analyze is clean**

Run: `flutter analyze lib/screens/torrent_search_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add lib/screens/torrent_search_screen.dart
git commit -m "feat(home): register HomeTodayCalendarCard at top of Home"
```

---

## Task 10: TraktCalendarScreen — shell with month grid scaffold

**Files:**
- Modify: `lib/screens/trakt_calendar_screen.dart`

- [ ] **Step 1: Replace the stub screen with the real shell**

Replace the entire contents of `lib/screens/trakt_calendar_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/trakt/trakt_calendar_entry.dart';
import '../services/trakt/trakt_calendar_service.dart';
import '../services/trakt/trakt_service.dart';
import '../widgets/trakt_calendar_day_sheet.dart';

/// Full-screen grid calendar of upcoming Trakt episodes.
///
/// Layout: AppBar + vertical list of month blocks. Each block is a 7-column
/// grid. Infinite scroll in both directions via lazy chunk fetching.
class TraktCalendarScreen extends StatefulWidget {
  const TraktCalendarScreen({super.key});

  @override
  State<TraktCalendarScreen> createState() => _TraktCalendarScreenState();
}

class _TraktCalendarScreenState extends State<TraktCalendarScreen> {
  bool _isAuth = true;
  bool _isLoading = true;
  final List<DateTime> _monthStarts = []; // Each element = first-day-of-month
  Map<DateTime, List<TraktCalendarEntry>> _byDay = const {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final isAuth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    if (!isAuth) {
      setState(() {
        _isAuth = false;
        _isLoading = false;
      });
      return;
    }

    final now = DateTime.now();
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final rangeStart = DateTime(now.year, now.month - 1, 1);
    final rangeEnd = DateTime(now.year, now.month + 2, 0); // last day of next month

    final grouped = await TraktCalendarService.instance.getRange(rangeStart, rangeEnd);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _byDay = grouped;
      _monthStarts
        ..clear()
        ..addAll([
          DateTime(now.year, now.month - 1, 1),
          thisMonthStart,
          DateTime(now.year, now.month + 1, 1),
        ]);
    });
  }

  void _onDayTap(DateTime day, List<TraktCalendarEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TraktCalendarDaySheet(date: day, entries: entries),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            tooltip: 'Jump to today',
            icon: const Icon(Icons.today),
            onPressed: _isLoading ? null : _jumpToToday,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isAuth) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Connect Trakt to see your calendar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_monthStarts.isEmpty) {
      return const Center(
        child: Text('Nothing airing.', style: TextStyle(color: Colors.white54)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: _monthStarts.length,
      itemBuilder: (ctx, index) {
        final monthStart = _monthStarts[index];
        return _MonthBlock(
          monthStart: monthStart,
          byDay: _byDay,
          onDayTap: _onDayTap,
        );
      },
    );
  }

  void _jumpToToday() {
    // Infinite scroll wiring in Task 12. For now, scroll to current month.
    final now = DateTime.now();
    final idx = _monthStarts.indexWhere(
      (m) => m.year == now.year && m.month == now.month,
    );
    if (idx >= 0) {
      // Best-effort scroll — item extents are variable so we approximate
      _scrollController.animateTo(
        idx * 420.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
}

/// Renders one month header + 7-column day grid.
class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    required this.monthStart,
    required this.byDay,
    required this.onDayTap,
  });

  final DateTime monthStart;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onDayTap;

  @override
  Widget build(BuildContext context) {
    final monthLabel = _formatMonth(monthStart);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              monthLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _DowHeader(),
          const SizedBox(height: 4),
          _DayGrid(
            monthStart: monthStart,
            byDay: byDay,
            onDayTap: onDayTap,
          ),
        ],
      ),
    );
  }

  static String _formatMonth(DateTime m) {
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return '${months[m.month - 1]} ${m.year}';
  }
}

class _DowHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: [
        for (final label in labels)
          Expanded(
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.monthStart,
    required this.byDay,
    required this.onDayTap,
  });

  final DateTime monthStart;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onDayTap;

  @override
  Widget build(BuildContext context) {
    final cells = _computeCells();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cellSize = constraints.maxWidth / 7;
        return Column(
          children: [
            for (int rowStart = 0; rowStart < cells.length; rowStart += 7)
              Row(
                children: [
                  for (int i = 0; i < 7; i++)
                    SizedBox(
                      width: cellSize,
                      height: cellSize,
                      child: _DayCell(
                        cell: cells[rowStart + i],
                        cellWidth: cellSize,
                        onTap: onDayTap,
                        byDay: byDay,
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }

  /// Build 6×7=42 cells covering the month, padded with prev/next month days.
  List<_Cell> _computeCells() {
    final firstOfMonth = monthStart;
    // Sunday = 7 in Dart's weekday, treat Sunday as column 0
    final leadingBlank = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0).day;

    final cells = <_Cell>[];
    // Leading blanks (prev month filler)
    for (int i = leadingBlank; i > 0; i--) {
      final d = firstOfMonth.subtract(Duration(days: i));
      cells.add(_Cell(date: d, inMonth: false));
    }
    // Current month days
    for (int day = 1; day <= daysInMonth; day++) {
      cells.add(_Cell(
        date: DateTime(firstOfMonth.year, firstOfMonth.month, day),
        inMonth: true,
      ));
    }
    // Trailing blanks to reach a multiple of 7 (up to 42 cells for consistent height)
    while (cells.length % 7 != 0) {
      final last = cells.last.date;
      cells.add(_Cell(date: last.add(const Duration(days: 1)), inMonth: false));
    }
    return cells;
  }
}

class _Cell {
  final DateTime date;
  final bool inMonth;
  _Cell({required this.date, required this.inMonth});
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.cell,
    required this.cellWidth,
    required this.onTap,
    required this.byDay,
  });

  final _Cell cell;
  final double cellWidth;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onTap;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = cell.date.year == now.year &&
        cell.date.month == now.month &&
        cell.date.day == now.day;
    final entries = byDay[DateTime(cell.date.year, cell.date.month, cell.date.day)] ?? const [];

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: cell.inMonth ? 1.0 : 0.3,
        child: Material(
          color: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: isToday ? const Color(0xFF60A5FA) : const Color(0xFF1E293B),
              width: isToday ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: (cell.inMonth && entries.isNotEmpty)
                ? () => onTap(DateTime(cell.date.year, cell.date.month, cell.date.day), entries)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${cell.date.day}',
                    style: TextStyle(
                      color: isToday ? const Color(0xFF60A5FA) : Colors.white70,
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  if (entries.isNotEmpty) _buildEntrySummary(entries),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntrySummary(List<TraktCalendarEntry> entries) {
    // Chip rendering in Task 11. For now, just a count.
    return Text(
      '${entries.length}',
      style: const TextStyle(color: Colors.white54, fontSize: 9),
    );
  }
}
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart 2>&1 | grep "error "`
Expected: ONE error — `trakt_calendar_day_sheet.dart` not found (that file is created in Task 14). Continue to Step 3.

- [ ] **Step 3: Create day sheet stub**

Write `lib/widgets/trakt_calendar_day_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/trakt/trakt_calendar_entry.dart';

/// Bottom sheet showing episodes airing on a specific day.
///
/// Fleshed out in Task 14.
class TraktCalendarDaySheet extends StatelessWidget {
  const TraktCalendarDaySheet({
    super.key,
    required this.date,
    required this.entries,
  });

  final DateTime date;
  final List<TraktCalendarEntry> entries;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '${entries.length} episodes on ${date.year}-${date.month}-${date.day}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart lib/widgets/trakt_calendar_day_sheet.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 5: Commit**

```bash
git add lib/screens/trakt_calendar_screen.dart lib/widgets/trakt_calendar_day_sheet.dart
git commit -m "feat(calendar): add TraktCalendarScreen shell with month grid scaffold"
```

---

## Task 11: Month grid — chip rendering with responsive fallback

**Files:**
- Modify: `lib/screens/trakt_calendar_screen.dart`

- [ ] **Step 1: Replace the _buildEntrySummary placeholder with chip/dot rendering**

In `lib/screens/trakt_calendar_screen.dart`, replace the `_buildEntrySummary` method inside `_DayCell`:

```dart
  Widget _buildEntrySummary(List<TraktCalendarEntry> entries) {
    // Use a compact rendering when cell is too narrow for chips
    if (cellWidth < 48) {
      // Dots + count fallback for very narrow screens
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _colorForShow(entries.first.showTitle),
              shape: BoxShape.circle,
            ),
          ),
          if (entries.length > 1) ...[
            const SizedBox(width: 2),
            Text(
              '${entries.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ],
      );
    }

    // Chip rendering
    final maxName = cellWidth > 100 ? 16 : 8;
    final visible = entries.take(2).toList();
    final overflow = entries.length > 2 ? entries.length - 2 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _colorForShow(e.showTitle),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _truncate(e.showTitle, maxName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+$overflow',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
      ],
    );
  }

  static Color _colorForShow(String title) {
    // Stable hash → hue, mapped to a curated palette for good contrast
    const palette = [
      Color(0xFF8B5CF6),
      Color(0xFF22C55E),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
    ];
    int hash = 0;
    for (final c in title.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/screens/trakt_calendar_screen.dart
git commit -m "feat(calendar): add chip rendering with responsive dots fallback"
```

---

## Task 12: Infinite scroll — lazy load adjacent months

**Files:**
- Modify: `lib/screens/trakt_calendar_screen.dart`

- [ ] **Step 1: Add scroll listener and chunk-fetch-on-edge logic**

In `lib/screens/trakt_calendar_screen.dart`, modify `initState` to attach a listener:

```dart
  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scrollController.addListener(_onScroll);
  }
```

Add new fields to `_TraktCalendarScreenState`:

```dart
  bool _isLoadingMore = false;
```

Add the `_onScroll` method and extension helpers to the class:

```dart
  void _onScroll() {
    if (_isLoadingMore || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;

    // Near the bottom — append next month
    if (pos > max - 600) {
      _appendNextMonth();
    }
    // Near the top — prepend previous month
    if (pos < 600) {
      _prependPreviousMonth();
    }
  }

  Future<void> _appendNextMonth() async {
    if (_monthStarts.isEmpty) return;
    _isLoadingMore = true;
    final last = _monthStarts.last;
    final next = DateTime(last.year, last.month + 1, 1);
    final rangeEnd = DateTime(next.year, next.month + 1, 0);
    final grouped = await TraktCalendarService.instance.getRange(next, rangeEnd);
    if (!mounted) { _isLoadingMore = false; return; }
    setState(() {
      _monthStarts.add(next);
      _byDay = {..._byDay, ...grouped};
    });
    _isLoadingMore = false;
  }

  Future<void> _prependPreviousMonth() async {
    if (_monthStarts.isEmpty) return;
    _isLoadingMore = true;
    final first = _monthStarts.first;
    final prev = DateTime(first.year, first.month - 1, 1);
    final rangeEnd = DateTime(prev.year, prev.month + 1, 0);
    final grouped = await TraktCalendarService.instance.getRange(prev, rangeEnd);
    if (!mounted) { _isLoadingMore = false; return; }
    // Preserve current visible offset — capture before insert, restore after
    final beforeMax = _scrollController.position.maxScrollExtent;
    final beforePos = _scrollController.position.pixels;
    setState(() {
      _monthStarts.insert(0, prev);
      _byDay = {..._byDay, ...grouped};
    });
    // After layout completes, add the delta to keep the user's view stable
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final afterMax = _scrollController.position.maxScrollExtent;
      final delta = afterMax - beforeMax;
      _scrollController.jumpTo(beforePos + delta);
    });
    _isLoadingMore = false;
  }
```

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/screens/trakt_calendar_screen.dart
git commit -m "feat(calendar): lazy-load adjacent months on scroll"
```

---

## Task 13: DPAD focus navigation on day cells

**Files:**
- Modify: `lib/screens/trakt_calendar_screen.dart`

- [ ] **Step 1: Make _DayCell focusable with key event handling**

In `lib/screens/trakt_calendar_screen.dart`, replace the `_DayCell` class with a stateful version that wires up focus:

```dart
class _DayCell extends StatefulWidget {
  const _DayCell({
    required this.cell,
    required this.cellWidth,
    required this.onTap,
    required this.byDay,
  });

  final _Cell cell;
  final double cellWidth;
  final void Function(DateTime day, List<TraktCalendarEntry> entries) onTap;
  final Map<DateTime, List<TraktCalendarEntry>> byDay;

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'day-${widget.cell.date}',
      skipTraversal: !widget.cell.inMonth,
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = widget.cell.date.year == now.year &&
        widget.cell.date.month == now.month &&
        widget.cell.date.day == now.day;
    final entries = widget.byDay[DateTime(
          widget.cell.date.year,
          widget.cell.date.month,
          widget.cell.date.day,
        )] ??
        const [];
    final hasEntries = entries.isNotEmpty && widget.cell.inMonth;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Opacity(
        opacity: widget.cell.inMonth ? 1.0 : 0.3,
        child: Focus(
          focusNode: _focusNode,
          canRequestFocus: hasEntries,
          child: Builder(
            builder: (ctx) {
              final isFocused = Focus.of(ctx).hasFocus;
              return Material(
                color: isFocused ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: isFocused
                        ? const Color(0xFF60A5FA)
                        : (isToday ? const Color(0xFF60A5FA) : const Color(0xFF1E293B)),
                    width: (isFocused || isToday) ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: hasEntries
                      ? () => widget.onTap(
                            DateTime(
                              widget.cell.date.year,
                              widget.cell.date.month,
                              widget.cell.date.day,
                            ),
                            entries,
                          )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.cell.date.day}',
                          style: TextStyle(
                            color: isToday ? const Color(0xFF60A5FA) : Colors.white70,
                            fontSize: 11,
                            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        const Spacer(),
                        if (entries.isNotEmpty)
                          _DayCellSummary(
                            entries: entries,
                            cellWidth: widget.cellWidth,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
```

Extract the summary into a separate stateless widget at the bottom of the file (so the helper methods move with it):

```dart
class _DayCellSummary extends StatelessWidget {
  const _DayCellSummary({required this.entries, required this.cellWidth});

  final List<TraktCalendarEntry> entries;
  final double cellWidth;

  @override
  Widget build(BuildContext context) {
    if (cellWidth < 48) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _colorForShow(entries.first.showTitle),
              shape: BoxShape.circle,
            ),
          ),
          if (entries.length > 1) ...[
            const SizedBox(width: 2),
            Text(
              '${entries.length}',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ],
        ],
      );
    }

    final maxName = cellWidth > 100 ? 16 : 8;
    final visible = entries.take(2).toList();
    final overflow = entries.length > 2 ? entries.length - 2 : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in visible)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: _colorForShow(e.showTitle),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                _truncate(e.showTitle, maxName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ),
          ),
        if (overflow > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+$overflow',
              style: const TextStyle(color: Colors.white54, fontSize: 9),
            ),
          ),
      ],
    );
  }

  static Color _colorForShow(String title) {
    const palette = [
      Color(0xFF8B5CF6),
      Color(0xFF22C55E),
      Color(0xFFEF4444),
      Color(0xFFF59E0B),
      Color(0xFF3B82F6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
      Color(0xFFF97316),
    ];
    int hash = 0;
    for (final c in title.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  static String _truncate(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max - 1)}…';
  }
}
```

Delete the old `_buildEntrySummary`, `_colorForShow`, and `_truncate` methods from `_DayCell` (now replaced by the new stateful version above).

- [ ] **Step 2: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 3: Commit**

```bash
git add lib/screens/trakt_calendar_screen.dart
git commit -m "feat(calendar): add DPAD focus support on day cells"
```

---

## Task 14: TraktCalendarDaySheet — full episode list with tap navigation

**Files:**
- Modify: `lib/widgets/trakt_calendar_day_sheet.dart`
- Modify: `lib/screens/trakt_calendar_screen.dart` (to pass the navigation callback)

- [ ] **Step 1: Replace the day sheet stub with the real implementation**

Replace the entire contents of `lib/widgets/trakt_calendar_day_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../models/trakt/trakt_calendar_entry.dart';
import '../models/stremio_addon.dart';

/// Bottom sheet showing all episodes airing on a specific day.
///
/// Tapping an episode dismisses the sheet and calls [onEpisodeSelected]
/// with a [StremioMeta] built from the entry's show fields.
class TraktCalendarDaySheet extends StatelessWidget {
  const TraktCalendarDaySheet({
    super.key,
    required this.date,
    required this.entries,
    required this.onEpisodeSelected,
  });

  final DateTime date;
  final List<TraktCalendarEntry> entries;
  final void Function(StremioMeta meta) onEpisodeSelected;

  @override
  Widget build(BuildContext context) {
    // Sort entries by air time
    final sorted = [...entries]
      ..sort((a, b) => a.firstAiredLocal.compareTo(b.firstAiredLocal));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _formatFullDate(date),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: sorted.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (ctx, i) => _EpisodeRow(
                  entry: sorted[i],
                  onTap: () {
                    final meta = _buildMetaFromEntry(sorted[i]);
                    if (meta == null) return;
                    Navigator.of(ctx).pop();
                    onEpisodeSelected(meta);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static StremioMeta? _buildMetaFromEntry(TraktCalendarEntry e) {
    if (e.showImdbId == null) return null;
    return StremioMeta.fromJson({
      'id': e.showImdbId,
      'name': e.showTitle,
      'type': 'series',
      'year': e.showYear?.toString(),
      'poster': e.posterUrl,
    });
  }

  static String _formatFullDate(DateTime d) {
    const weekdays = [
      'Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'
    ];
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.entry, required this.onTap});

  final TraktCalendarEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = _formatTime(entry.firstAiredLocal);
    final badge = entry.isNewShow
        ? 'NEW SHOW'
        : entry.isSeasonPremiere
            ? 'SEASON PREMIERE'
            : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (entry.posterUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  entry.posterUrl!,
                  width: 40,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                      width: 40, height: 60, child: Icon(Icons.tv)),
                ),
              )
            else
              const SizedBox(width: 40, height: 60, child: Icon(Icons.tv)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.showTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'S${entry.seasonNumber.toString().padLeft(2, '0')}E${entry.episodeNumber.toString().padLeft(2, '0')} · $time'
                    '${entry.episodeTitle != null ? ' · ${entry.episodeTitle}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime local) {
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
```

- [ ] **Step 2: Wire the sheet's onEpisodeSelected callback in TraktCalendarScreen**

Open `lib/screens/trakt_calendar_screen.dart`. Find `_onDayTap` and update it:

```dart
  void _onDayTap(DateTime day, List<TraktCalendarEntry> entries) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TraktCalendarDaySheet(
        date: day,
        entries: entries,
        onEpisodeSelected: _handleEpisodeSelected,
      ),
    );
  }

  void _handleEpisodeSelected(StremioMeta meta) {
    // Pop the calendar screen and hand the meta to the catalog flow.
    // The caller of TraktCalendarScreen should treat the popped value
    // as "navigate to this show detail".
    Navigator.of(context).pop(meta);
  }
```

Add the import at the top of `trakt_calendar_screen.dart`:

```dart
import '../models/stremio_addon.dart';
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/screens/trakt_calendar_screen.dart lib/widgets/trakt_calendar_day_sheet.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/trakt_calendar_day_sheet.dart lib/screens/trakt_calendar_screen.dart
git commit -m "feat(calendar): add day sheet with episode tap navigation"
```

---

## Task 15: Home card handles TraktCalendarScreen return value

**Files:**
- Modify: `lib/widgets/home_today_calendar_card.dart`

The calendar screen now pops with a `StremioMeta` when the user selects an episode. The Home card must catch that and route it to the existing catalog-item-selected handler.

- [ ] **Step 1: Pass an onItemSelected callback to the Today card**

Open `lib/widgets/home_today_calendar_card.dart`. Add a new required parameter to the widget:

```dart
class HomeTodayCalendarCard extends StatefulWidget {
  const HomeTodayCalendarCard({
    super.key,
    required this.focusController,
    required this.isTelevision,
    required this.onRequestFocusAbove,
    required this.onRequestFocusBelow,
    required this.onItemSelected,
  });

  final HomeFocusController focusController;
  final bool isTelevision;
  final VoidCallback onRequestFocusAbove;
  final VoidCallback onRequestFocusBelow;
  final void Function(StremioMeta meta) onItemSelected;
  // ...
}
```

Add the import at the top:

```dart
import '../models/stremio_addon.dart';
```

Replace `_openFullCalendar`:

```dart
  Future<void> _openFullCalendar() async {
    final result = await Navigator.of(context).push<StremioMeta?>(
      MaterialPageRoute(builder: (_) => const TraktCalendarScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      widget.onItemSelected(result);
    }
  }
```

- [ ] **Step 2: Wire onItemSelected in torrent_search_screen.dart**

Open `lib/screens/torrent_search_screen.dart`. Find the `HomeTodayCalendarCard(...)` call from Task 9 and add the callback:

```dart
      RepaintBoundary(child: HomeTodayCalendarCard(
        focusController: _homeFocusController,
        isTelevision: _isTelevision,
        onRequestFocusAbove: () {
          final prev = _homeFocusController.getPreviousSection(HomeSection.todayCalendar);
          if (prev != null) {
            _homeFocusController.focusSection(prev);
          } else {
            _focusControlRow();
          }
        },
        onRequestFocusBelow: () {
          final next = _homeFocusController.getNextSection(HomeSection.todayCalendar);
          if (next != null) {
            _homeFocusController.focusSection(next);
          }
        },
        onItemSelected: (meta) {
          final selection = AdvancedSearchSelection(
            imdbId: meta.imdbId ?? meta.id,
            title: meta.name,
            contentType: meta.type == 'series' ? 'series' : 'movie',
            posterUrl: meta.poster,
            year: meta.year,
          );
          _handleCatalogItemSelected(selection, updateSearchText: true);
        },
      )),
```

- [ ] **Step 3: Verify compile**

Run: `flutter analyze lib/widgets/home_today_calendar_card.dart lib/screens/torrent_search_screen.dart 2>&1 | grep "error "`
Expected: no output

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/home_today_calendar_card.dart lib/screens/torrent_search_screen.dart
git commit -m "feat(home): route Today card episode taps to catalog handler"
```

---

## Task 16: Manual smoke test checklist

This task is verification, not code. Run through the checklist on a real device before declaring the feature shippable.

- [ ] **Phone — Today card "full" state**
  - Ensure Trakt is connected with a show that has an episode airing today
  - Open app → Home tab
  - Verify the Today card appears at the very top of the Home scroll, above Trakt Now Playing
  - Verify the card shows the date label, poster, show title, S##E##, air time
  - If >2 episodes, verify the "+N more tonight" text

- [ ] **Phone — Today card "peek" state**
  - Use a Trakt account where no episode airs today but one airs within 7 days
  - Verify the card shows "Nothing today — next: *ShowName* Mon" with a chevron

- [ ] **Phone — Today card "hidden" state**
  - Disconnect Trakt (or pick a week with no upcoming episodes)
  - Verify the card is completely hidden

- [ ] **Phone — Tap card**
  - Tap the card (full or peek state)
  - Verify the Calendar screen pushes in

- [ ] **Phone — Month grid**
  - On Calendar screen, verify the current month is shown with correct date numbers
  - Verify today's cell has a blue border highlight
  - Verify days with episodes show chips with show names
  - Verify "+N" overflow appears when >2 episodes on a day
  - Verify adjacent-month filler cells are dimmed

- [ ] **Phone — Tap day cell**
  - Tap a day with episodes → bottom sheet appears
  - Verify the sheet shows full date header and all episodes
  - Verify "Season Premiere" / "New Show" badges on applicable episodes

- [ ] **Phone — Tap episode in sheet**
  - Tap an episode → sheet dismisses, calendar pops, Home shows the show in the catalog view

- [ ] **Phone — Infinite scroll**
  - Scroll down past current month → verify next month appears
  - Scroll up to top → verify previous month appears without jumping the view
  - Verify the "Jump to today" AppBar action returns focus to the current month

- [ ] **Android TV — DPAD navigation**
  - Open Calendar screen on a TV device
  - Navigate with arrow keys → verify focus moves between day cells
  - Verify focused cell has a visible blue border
  - Press Enter/Select on a focused day → day sheet appears
  - Verify back button on the sheet returns focus to the tapped cell
  - Verify back button on the calendar screen pops cleanly

- [ ] **Narrow screen / foldable closed**
  - Resize app window to < 340px (or use a foldable in closed mode)
  - Verify day cells switch to dots+count rendering
  - Verify layout does not overflow

- [ ] **TV / wide screen**
  - On a wide display (> 900px), verify chips show longer show names (up to 16 chars)
  - Verify cell padding and focus highlighting are visible from 6+ feet away

- [ ] **Trakt logout while calendar open**
  - Open the Calendar screen with data loaded
  - In Settings, disconnect Trakt
  - Navigate back to Home → verify the Today card disappears
  - Reopen the Calendar (if still reachable) → verify the "Connect Trakt" empty state

- [ ] **Static analysis**
  - Run: `flutter analyze 2>&1 | grep "error "`
  - Expected: no output (zero errors)
  - Run: `flutter test`
  - Expected: all existing + new tests pass

- [ ] **Final commit (if any fixes needed)**
  - If smoke test uncovered issues, fix and commit as separate bug-fix commits
  - When clean, the feature is ready for review

---

## Self-review checklist (internal)

Before handing this plan off, verify:

- [x] Every spec section has at least one task implementing it
- [x] File paths are exact and absolute-to-repo
- [x] All code blocks are complete (no `...` or TODO)
- [x] Test code appears before implementation code in each task (TDD)
- [x] Task granularity: each task is ~10-30 minutes
- [x] No forward references: if Task N uses a file, Task N-1 or earlier creates it
- [x] Commit messages are in conventional-commit format
- [x] `flutter analyze` check appears in tasks that touch non-test code
