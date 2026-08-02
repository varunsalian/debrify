# Recordings Hub — "Scheduled" becomes the DVR's front door

Goal: rename the rail's **Scheduled** entry to **Recordings** and grow the page
behind it from a schedule list into a full DVR hub: what's recording right now
(stoppable), what's coming up (cancellable, schedulable), and every finished
recording — playable in-app with one press.

## The three zones (one scrollable page, `RecordingsPage`)

1. **RECORDING NOW** — live cards. Channel name, elapsed (1s local tick),
   bytes written, red REC treatment, a Stop button per card.
   - Android: `LiveRecordingService.query()` where `isRecording`; 3s poll
     while the page is visible refreshes bytes (reconcile-first on a worker
     thread natively — cheap).
   - Desktop: `DesktopRecordingService.instance.active`; bytes read straight
     off the capture object each tick, stop via `capture.stop()`.
2. **SCHEDULED** — ported from the old page: rows + confirm-cancel, the
   exact-alarms banner, and the manual channel+time+duration flow (now a
   header **Schedule** button instead of a FAB — reachable in DPAD scroll
   order). Countdown chip per row ("in 2h 15m") off the same 1s tick.
3. **LIBRARY** — finished recordings, newest first. Monogram thumb + play
   glyph, 2-line title, "channel · date · size · duration", trailing delete.
   OK/tap plays IN-APP via `VideoPlayerLauncher.push` (native ExoPlayer on
   TV — plays `content://`/`file://` natively; media_kit elsewhere — its
   `AndroidContentUriProvider` handles `content://` on phones).
   `disableExternalPlayer: true` on Android (an external intent can't read
   our unshared content URI); desktop keeps the user's external default
   (plain file paths work in IINA/VLC).

Style: IPTV cockpit tokens (bg #070A18, REC #F43F5E, gold TV focus ring,
purple selection), not settings-Material — this page belongs to the DVR
world. Single 1s `ValueNotifier<DateTime>` drives elapsed/countdown text via
scoped `ValueListenableBuilder`s (no whole-page per-second rebuilds; ticker
runs only while something is live or scheduled). No new animations on TV
(REC dot pulses on phone/desktop only, `isAndroidTvCached`-gated).

## Data-layer changes

### Android (Kotlin)
- **`RecordingTaskStore.reconcileDeadEntries` retention change**: a
  `done && published` entry now lives as long as its file does (existence
  check via `fileSize(uri) < 0` → remove) instead of the 24h TTL — the store
  IS the library index, and a TTL would silently empty the library. Guarded
  by `LiveRecordingService.isSupported(context)` so a revoked legacy grant
  (exists() would lie "false") can't mass-prune real files. `done` with no
  uri, and `failed`, keep the TTL. `done && !published` whose row vanished
  entirely also gets removed (today it would retry publish forever).
- **`queryRecordingsLibrary`** (new channel method, worker thread):
  store entries (`done`, has uri) enriched with channelName + duration
  (`updatedAt - startedAtMs`, sanity-clamped), MERGED with a MediaStore scan
  of our own rows under `Download/Debrify/Recordings` (Q+; pending rows are
  excluded by default) and a legacy dir listing (pre-Q, only when granted).
  The scan is what makes tee-recorded files and **recordings whose entries
  the old 24h TTL already pruned** (the user's existing test recordings!)
  appear. Match store↔scan by MediaStore row id.
- **`deleteRecordingFile`** (new): refuses while that task is live in the
  registry; `deleteDestination(uri)` + drop any store entry with that uri.

### Dart
- `LiveRecordingService`: `RecordingLibraryEntry` model + `queryLibrary()` +
  `deleteRecordingFile(...)`.
- `DesktopScheduleService.recordingsDir()` extracted from `_targetPath` (one
  truth for where recordings live); desktop library = list that dir for
  `.ts/.mkv/.mp4/.m2ts`, skipping the active capture's growing file. Name
  prettified from `Channel_Name_YYYYMMDD_HHMMSS[_N].ts`; duration ≈ mtime −
  stamp when sane.

## Renames (user-visible strings only; internal prop names keep)
- `IptvCommandRail`: label 'Scheduled' → **'Recordings'** (+ doc comment).
  Badge stays = upcoming schedules; liveDot stays = capturing now.
- `iptv_results_view._openScheduledRecordings` → pushes `RecordingsPage`.
- IPTV settings (both layouts): row 'Scheduled recordings' → **'Recordings'**
  (count phrasing "N scheduled" kept in subtitles); opens `RecordingsPage`.
- Settings-search: description + keywords gain 'library'/'dvr'.
- `lib/screens/settings/scheduled_recordings_page.dart` → replaced by
  `lib/screens/settings/recordings_page.dart` (schedule/cancel/manual-timer
  logic ported verbatim where it was already right).

## Refresh model
initState load (parallel) · `schedulesRevision` + desktop `revision`
listeners · 3s Android live poll while visible · lifecycle-resume full
reload · reload after every action. Rail badge/live-dot on the IPTV page
keeps its existing plumbing untouched.

## Explicitly NOT in this step
Thumbnails (frame extraction), rename/share actions, per-recording detail
sheet, Android "Open with…" external chooser, recordings search/filter.
