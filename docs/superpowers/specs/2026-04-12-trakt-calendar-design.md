# Trakt Calendar — Design

**Date:** 2026-04-12
**Status:** Design approved, awaiting implementation plan
**Owner:** Varun Salian
**Branch target:** 0.3.2 (or successor)

## Goal

Add a grid-calendar feature that shows upcoming episodes from the user's Trakt account. Two user-facing surfaces:

1. A **Today card** pinned at the top of the Home screen that peeks at what's airing today (or the next upcoming episode on quiet days).
2. A **full-screen grid calendar**, reachable by tapping the card, with a month-grid view and infinite vertical scroll through past and future months.

Positioning: this is a "special feature" of the app — prominent, daily-use, reactive to the user's schedule.

## Scope

### In scope
- Fetching upcoming episodes from Trakt's `/calendars/my/shows` endpoint
- Client-side detection of "New Show" (S01E01) and "Season Premiere" (any SxxE01) badges
- Today card on Home with full / peek / hidden states
- Full-screen calendar with month grid, chips-in-cell layout, responsive fallback, DPAD navigation
- Day detail bottom sheet with tappable episode rows
- In-memory chunked cache with 15-min TTL
- Cache invalidation on Trakt logout

### Out of scope (MVP)
- Notifications / reminders for upcoming episodes
- Movie / DVD / custom-list calendar endpoints
- Persisted cache across app restarts
- User-configurable first-day-of-week
- Filters (premieres-only, hide watched, etc.)
- User-customizable show chip colors
- Integration with bound sources or quick-play (tap actions deliberately route to info screens only)

## Non-goals

- We are not building a general "upcoming content" hub. This is Trakt-specific. Users without Trakt connected see nothing.
- We are not caching calendar data across app restarts. 15-min in-memory TTL is the entire cache story for MVP.
- We are not trying to unify calendar data with the existing Trakt Continue Watching section — they serve different purposes (retrospective vs. prospective) and live in different widgets.

## User-facing behavior

### Today card states

| State | Trigger | Render |
|---|---|---|
| **Hidden** | Trakt not connected, OR nothing airing in the next ~7 days | `SizedBox.shrink()` |
| **Loading** | First fetch in flight | Thin skeleton row at the card height, no spinner |
| **Full** | ≥1 episode airing today | Header ("Today · Sat, Apr 11") + 1-2 episode rows with poster / show / S##E## / air time. If >2 episodes, second row becomes "+N more tonight" chip |
| **Peek** | Nothing today, but ≥1 episode in next 7 days | Single-line card: "Nothing airing today — next: *Severance* Mon" + right chevron |

Whole card is tappable in full and peek states → pushes `TraktCalendarScreen`. Tapping an individual episode row in the full state does the same thing (consistent affordance; no split action).

### Full calendar screen

- AppBar with back button, title "Calendar", and a "Jump to today" action
- Body is a vertically-scrolling list of month blocks
- Each month block = header (e.g., "April 2026") + 7-column grid
- Grid cells render date number + stacked show chips (max 2 + "+N" overflow)
- Today's cell is highlighted with `#60A5FA` border
- Out-of-month filler cells are dimmed (30% opacity) and non-tappable
- **Responsive fallback:** when `constraints.maxWidth / 7 < 48px` (very narrow screens), cells switch to a dots+count rendering to stay legible. Standard 360px phones fit chips (≈51px cells).
- **Wide / TV:** when `maxWidth > 900`, cells grow to ~96px and chips show full (untruncated) show names where possible
- **DPAD navigation (Android TV):** arrow keys move focus between cells left-to-right / top-to-bottom, Enter opens the day sheet, Back pops the sheet or the screen

### Day detail sheet

- Modal bottom sheet, rounded top corners, matches existing bottom-sheet style
- Header: full date ("Saturday, April 11")
- List of episodes airing that day, each showing: small poster, show title, SxxExx, episode title, air time (local), badge for "New Show" / "Season Premiere" when applicable
- Tap an episode → dismiss sheet, push show detail screen using the same route catalog/search uses for `StremioMeta` item taps (build a lightweight `StremioMeta` from `showImdbId` + title + poster)

### Tap action mapping

| Surface | Action |
|---|---|
| Today card (anywhere) | Push `TraktCalendarScreen` |
| Day cell in grid | Open `TraktCalendarDaySheet` for that date |
| Episode row in sheet | Dismiss sheet, push show detail (existing `onItemSelected` route) |

## Architecture

### Approach

Dedicated `TraktCalendarService` layer between `TraktService` (raw HTTP) and the UI widgets. Service owns the chunk cache and the range-to-chunks math. Widgets are thin consumers that call `getRange()` for their window and render.

### File layout

**New files:**
- `lib/models/trakt/trakt_calendar_entry.dart` — domain model for a single calendar item
- `lib/services/trakt/trakt_calendar_service.dart` — singleton service with chunk cache
- `lib/widgets/home_today_calendar_card.dart` — Today card widget on Home
- `lib/screens/trakt_calendar_screen.dart` — full grid calendar screen
- `lib/widgets/trakt_calendar_day_sheet.dart` — day detail bottom sheet

**Modified files:**
- `lib/services/trakt/trakt_service.dart` — add `fetchCalendarMyShows(startDate, days)` method that does the raw HTTP call and reuses the existing 401→refresh→retry pattern; returns raw decoded JSON
- `lib/widgets/home_focus_controller.dart` — add `HomeSection.todayCalendar` enum variant
- `lib/screens/torrent_search_screen.dart` — register the new section in `_buildHomeSection()` at position 0 (top, above Trakt Now Playing)
- Trakt logout flow in `trakt_service.dart` — call `TraktCalendarService.instance.invalidate()`

### Model: `TraktCalendarEntry`

```dart
class TraktCalendarEntry {
  final DateTime firstAiredUtc;      // parsed from response.first_aired
  final DateTime firstAiredLocal;    // computed firstAiredUtc.toLocal()
  final String showTitle;
  final int? showYear;
  final String? showImdbId;
  final int? showTraktId;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? episodeOverview;
  final int? runtimeMinutes;
  final String? posterUrl;           // resolved via existing TraktItemTransformer fallback
  bool get isNewShow => seasonNumber == 1 && episodeNumber == 1;
  bool get isSeasonPremiere => episodeNumber == 1;

  static TraktCalendarEntry? fromTraktJson(Map<String, dynamic> json);
}
```

`fromTraktJson` returns `null` for entries missing `first_aired` or essential show fields; callers filter nulls.

### Service: `TraktCalendarService`

```dart
class TraktCalendarService {
  static final instance = TraktCalendarService._();
  TraktCalendarService._();

  static const int _chunkDays = 33;                  // Trakt API max
  static const Duration _ttl = Duration(minutes: 15);

  final Map<String, _CachedChunk> _chunkCache = {};

  /// Fetch or return-cached a single 33-day chunk aligned to Monday boundaries.
  Future<List<TraktCalendarEntry>> getChunk(
    DateTime chunkStart, {
    bool force = false,
  });

  /// Fetch [start, end] inclusive. Splits into chunks, dispatches in parallel,
  /// merges and de-dupes by (showTraktId, season, episode), groups by local date.
  Future<Map<DateTime, List<TraktCalendarEntry>>> getRange(
    DateTime start,
    DateTime end,
  );

  /// Drop all cached chunks. Call on Trakt logout.
  void invalidate();

  /// Align any date to its chunk's Monday start.
  DateTime _chunkStartFor(DateTime date);
}

class _CachedChunk {
  final List<TraktCalendarEntry> entries;
  final DateTime fetchedAt;
  _CachedChunk(this.entries, this.fetchedAt);
  bool get isFresh => DateTime.now().difference(fetchedAt) < TraktCalendarService._ttl;
}
```

**Cache key strategy:** chunks are 33-day windows that always start on a Monday. `_chunkStartFor(date)` returns the Monday on or before `date` (walking back 0-6 days). Any `getChunk(chunkStart)` call first aligns its argument. This means repeated calls for overlapping ranges hit the same cache keys deterministically and never overlap.

**Error handling:** `getChunk` catches all exceptions, logs via `debugPrint('TraktCalendarService: chunk fetch failed: $e')`, and returns `[]`. `getRange` merges whatever chunks succeed — partial results are better than nothing. Widgets do not see exceptions from this layer.

### Data flow

```
Home screen init
  └─ HomeTodayCalendarCard.initState
     └─ TraktCalendarService.getRange(today, today + 7 days)
        └─ (splits into 1-2 chunks) getChunk for each
           └─ cache hit? return cached
           └─ cache miss? TraktService.fetchCalendarMyShows → parse → cache → return
        └─ merge + group by local date → Map<DateTime, List<TraktCalendarEntry>>
     └─ pick entries for today; pick peek if today empty; setState

Tap card
  └─ Navigator.push(TraktCalendarScreen)

Calendar screen init
  └─ TraktCalendarService.getRange(currentMonthStart - 33d, currentMonthEnd + 33d)
  └─ render month blocks for current ±1 month
Scroll to edge
  └─ TraktCalendarService.getChunk(nextChunkStart) lazily
  └─ append / prepend month block

Tap day cell
  └─ showModalBottomSheet(TraktCalendarDaySheet, entries for that date)

Tap episode in sheet
  └─ Navigator.pop(sheet)
  └─ Navigator.push(show detail, built from entry.showImdbId + title + posterUrl)
```

## Error handling summary

| Scenario | Behavior |
|---|---|
| Trakt not authenticated | Today card: `SizedBox.shrink()`. Calendar screen: "Connect Trakt" empty state with settings link |
| 401 during fetch | Handled by `TraktService`'s existing refresh-retry |
| Network error | `getChunk` returns `[]`, logs via `debugPrint`. `getRange` returns partial results. Card stays hidden if data empty |
| Calendar screen network error on first open | Centered retry state with "Try again" button (distinguishable from legitimately-empty ranges) |
| Trakt logout while screen is mounted | `invalidate()` flushes cache; auth-state listeners in the card / screen rebuild into unauthenticated state |
| Entry missing `first_aired` | `fromTraktJson` returns `null`, caller drops |
| Entry missing poster URL | Fall back to generic placeholder icon (same as Trakt Continue Watching) |
| Duplicate entries across chunks | De-duped in `getRange` by `(showTraktId, season, episode)` |

## Timezone handling

- Trakt `first_aired` is UTC ISO-8601. Parse with `DateTime.parse(iso)` (Flutter returns UTC `DateTime`).
- Store both `firstAiredUtc` and `firstAiredLocal = firstAiredUtc.toLocal()` on the entry.
- All date-bucket keys in `Map<DateTime, List<TraktCalendarEntry>>` are **local** midnights: `DateTime(local.year, local.month, local.day)`.
- DST handled correctly via `DateTime(year, month, day)` construction (no time component).
- We trust device local time; wrong device clock produces wrong "today" but that's consistent with every other time-sensitive feature in the app.

## Integration with existing code

### Home screen placement

- `HomeSection` enum gains a new variant: `todayCalendar`
- `HomeFocusController._lastFocusedIndex` gets an entry for the new section
- `torrent_search_screen.dart:_buildHomeSection()` inserts the card at the top of the sections list (position 0, above `HomeTraktNowPlayingCard`)
- `HomeTodayCalendarCard` registers with `focusController.registerSection()` in its `_loadItemsInner()` the same way existing Home widgets do
- Standard DPAD wiring: `onRequestFocusAbove` / `onRequestFocusBelow` callbacks match the established pattern in `HomeTraktContinueWatchingSection`

### Trakt service integration

- `fetchCalendarMyShows` method added to `trakt_service.dart` follows the same shape as `fetchPlaybackItems()`:
  ```dart
  Future<List<Map<String, dynamic>>> fetchCalendarMyShows({
    required DateTime startDate,
    required int days,
  }) async { ... }
  ```
- Uses `_apiHeaders(accessToken: token)` with `extended=full` query param
- 401→refresh retry uses the existing `_withAccessTokenRetry()` helper if present, else replicates the pattern from `fetchPlaybackItems`

### Logout hook

- The existing `TraktService.logout()` method (line 26-92 of `trakt_service.dart`) gains one new line: `TraktCalendarService.instance.invalidate();`

## Responsive design strategy

The chips-in-cell layout is the baseline for all screen sizes. Responsive behavior per `LayoutBuilder`:

| Breakpoint (cell width ≈ `maxWidth / 7`) | Rendering |
|---|---|
| `< 48px` (very narrow — foldables closed, small widgets) | Dots + count indicator (e.g., "3") instead of chips |
| `48-100px` (typical phones / tablets) | Chips truncated to ~8 chars, max 2 + "+N" |
| `> 100px` (laptops, TV, large tablets) | Chips show full show names where they fit, max 2 + "+N" |

Day cells are always square (aspect-ratio 1:1). Font sizes scale with cell size. TV (> 900px total width) additionally applies: larger cell padding, bolder focused-cell highlighting (for DPAD visibility), and no hover states.

## Testing strategy

### Unit tests
- `TraktCalendarService`: chunk alignment math, cache hit / miss / TTL expiry, range splitting, merge-and-group output, de-duplication, `invalidate()`. Mock `TraktService.fetchCalendarMyShows` with a fake.
- `TraktCalendarEntry.fromTraktJson`: parametric tests over sample Trakt responses — valid today, valid tomorrow, missing `first_aired`, missing show fields, malformed date string, nested poster extraction.

### Widget tests
- `HomeTodayCalendarCard` smoke tests for each state (hidden / loading / full / peek) with an injected fake service.
- `TraktCalendarScreen` smoke test: fixed dataset, verify month grid renders the right cells with the right chips.

### Manual smoke tests (required pre-ship)
- Real Trakt account on phone: card appears, tap opens calendar, scroll past/future months, tap day → sheet, tap episode → show detail
- Android TV: DPAD navigation through cells, focus visibility, back-button behavior
- Narrow phone: chip fallback to dots+count renders correctly
- Trakt logout: card disappears, calendar screen cache is invalidated

### Not tested
- Real Trakt API integration tests — too flaky, account-dependent
- Long-running soak tests of infinite scroll cache growth — unbounded memory is theoretically possible but 33-day chunks are ~16KB each, so even 100 chunks is <2MB; won't be a problem in practice

## Risks and open questions

- **Risk:** TV DPAD navigation across month boundaries could feel choppy if we don't preload the adjacent month's chunk before the user scrolls into it. Mitigation: prefetch the next chunk on cell focus near the edge of the visible month.
- **Risk:** The first-day-of-week choice (Sun vs Mon) is culturally sensitive. MVP ships with Sunday (matches US convention and is simpler to implement). Future setting can let the user override.
- **Open question:** How does the `TraktItemTransformer` poster fallback chain behave for shows that have no IMDB ID? Needs verification during implementation — worst case, entries without IMDB fall back to a generic icon.
- **Open question:** Does the existing `HomeFocusController` handle section insertions at position 0 correctly, or does adding a new section shift all existing indices and break saved focus state? Needs a quick check during implementation.

## Success criteria

- Card appears on Home when Trakt is connected and there's upcoming content in the next 7 days
- Card is hidden (not broken, not error-ing) when Trakt is disconnected or there's nothing airing
- Tapping the card opens the calendar screen within 1 frame (no loading dialog between)
- Calendar screen renders the current month grid on open using cached data when available
- Scrolling into adjacent months lazy-loads within <500ms on typical networks (cached chunks are instant)
- DPAD navigation on Android TV reaches every day cell and never gets stuck
- On narrow screens, the dots+count fallback renders legibly; on TV, chips show full show names
- Trakt logout immediately invalidates the cache (no stale data leaking to the next account)
- Zero new `flutter analyze` errors; existing warnings unchanged
