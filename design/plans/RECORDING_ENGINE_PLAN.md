# Recording Engine — Implementation Plan (Phases A / B / C)

The in-player tee (libmpv `stream-record`, ExoPlayer `RecordingDataSource`) records
only what is being watched and dies with the player. This plan adds a **standalone
recording engine**: a native foreground service that opens its OWN connection to a
live stream and pumps bytes to a MediaStore file, independent of any player — the
foundation for background recording, zap-proof recording, watch-A-record-B, and
scheduled (EPG) recordings with the app closed.

Modeled directly on `MediaStoreDownloadService` (foreground lifecycle, persisted
task store, reconciliation, notifications, wake/wifi locks): a live recording is a
download whose end is a stop command instead of an EOF.

## Scope / non-goals (v1)

In scope:
- Phase A: `LiveRecordingService` (progressive/TS streams), Dart API, Record
  buttons on the native TV player and the Dart player (Android) start engine
  recordings; tee kept as fallback (flag) and as the HLS path on the Dart player.
- Phase B: notification with Stop + elapsed/size, REC state in both players,
  recording survives zap/Home/app-kill, concurrent cap (2), Dart query API.
- Phase C: one-shot scheduled recordings via exact alarms — native schedule
  store, `RecordingAlarmReceiver`, boot re-registration + missed-alarm late-join,
  "Record" on future EPG programmes (Dart schedule surfaces + native TV guide),
  scheduled-recordings management UI in IPTV settings.

Not in v1 (unchanged from the DVR gap list):
- HLS/DASH **engine** recording (the Dart player's mpv tee still records HLS-TS
  while watching — that path is kept precisely because the engine can't do it).
- Timeshift/ring buffers, pause/resume, MP4 remux, recordings library screen,
  Stremio-addon channels in *scheduled* recordings (needs Dart to resolve; the
  in-player Record button still works for them via the resolved URL), repeat
  schedules, SAF destinations for recordings, sub-Android-10 recording.

## Architecture decisions

1. **Sibling service, not an extension of `MediaStoreDownloadService`.**
   `LiveRecordingService` is a new file in `com.debrify.app.recording`, copying
   the download service's hardened idioms (foreground-first onStartCommand,
   AtomicBoolean claim/finish guards, main-handler stop paths, watchdog) rather
   than sharing code with it. The download service is reviewer-hardened and
   shipping; recording must not be able to regress it. Duplication is the cost,
   and it is acceptable.

2. **Engine records via its own HTTP connection.** Costs a second connection when
   recording the channel being watched (matters on `max_connections=1` Xtream
   accounts — documented caveat, surfaced in the snackbar copy). In exchange the
   recording is immune to zaps, source switches, Home, player death, app death.

3. **Destination: MediaStore `Download/Debrify/Recordings`, API 29+ only** —
   identical to the tee's publishing idiom. The file is written IN PLACE via an
   `IS_PENDING=1` row (no temp copy, no double space, unlike the phone tee path).
   `IS_PENDING` is cleared on stop. On failure the row is deleted only when it
   holds nothing; a row with bytes is finalized as a partial recording.

4. **Stopping conditions:** user (button, notification action), duration cap
   (scheduled recordings; also a global 6h safety cap), low disk (<200 MB free at
   start refuses; write failing mid-stream finalizes what exists), stall
   watchdog (live stream silent for 60s → reconnect with fresh connection, up to
   3 consecutive failures → finalize partial).
   NO auto-stop on lifecycle events — that is the whole point.

5. **Flag: `flutter.recording_engine_enabled` (default ON).** Dart writes it via
   shared_preferences; Kotlin reads it from `FlutterSharedPreferences` (same
   pattern as `trailerUnderlayEnabled`). OFF = the session-hardened tee behavior
   everywhere (and scheduling UI hidden). Toggle lives in IPTV settings.

6. **Dart player routing (Android):** on Record, ask mpv what it is playing
   (`file-format` / `demuxer-via-network` property via NativePlayer.getProperty;
   if the probe is unavailable or fails, fall back to the URL heuristic, and on
   ambiguity choose the TEE — it records everything mpv can play). Segmented
   (hls/dash) → Xtream-rewrite to `.ts` if possible → engine; otherwise tee
   (only thing that can record true HLS; keeps today's behavior incl. auto-stop
   semantics). Progressive → engine. Desktop always tee. Distinct snackbar copy
   tells the user which semantics they got ("recording in background — stop from
   the notification" vs "stops if you leave the channel"). The tee auto-stop
   paths (`_switchToIptvChannel`, `_tryOpenLiveStream`, lifecycle onPause,
   dispose) stay tee-only: they check `_isRecording` (tee state) and never touch
   the engine task id.

7. **Native TV player routing:** engine replaces the tee whenever the flag is ON
   (the existing `isCurrentIptvSegmented()` gate already restricts to
   progressive, so nothing is lost). Tee code stays compiled and reachable with
   the flag OFF. The tee auto-stop calls (zap, `beginIptvPlayback`, `onStop`,
   `onDestroy`) are left EXACTLY as they are — they only touch
   `iptvRecordingController`, are no-ops when the tee is idle, and know nothing
   about engine tasks. No short-circuiting, no new branches on those paths.

7b. **Xtream `.m3u8 → .ts` rewrite.** Xtream panels serve every live channel in
   both containers (`/live/user/pass/id.m3u8` ⇄ `.ts`). When a channel is
   segmented ONLY because its playlist handed out the `.m3u8` form, the engine
   records the `.ts` twin instead. This turns most "HLS" Xtream channels into
   engine-recordable ones (native TV Record button included) and makes them
   schedulable. Applied only on a strict `/live/{u}/{p}/{id}.m3u8` path match;
   a panel that 404s the twin fails the recording with a clear notification.

8. **Schedules are native-owned.** `RecordingScheduleStore` (SharedPreferences
   JSON, same idiom as `DownloadTaskStore`) holds one-shot schedules with a URL +
   headers snapshot taken at schedule time. Alarm fire needs no Flutter engine.
   Dart reads/writes through new channel methods. Stremio channels are excluded
   from scheduling in v1 (their URLs resolve through Dart-side closures).

9. **Exact alarms:** manifest declares BOTH `SCHEDULE_EXACT_ALARM` (granted by
   default on Android 12, where `USE_EXACT_ALARM` doesn't exist) and
   `USE_EXACT_ALARM` (auto-granted on 13+; acceptable for a sideloaded app —
   revisit if Play distribution ever happens). Code still checks
   `canScheduleExactAlarms()` and falls back to `setWindow` (~10 min slop) with
   the state reported to Dart so the UI can warn.

10. **FGS start legality:** alarm receivers for exact alarms are on the
    background-start exemption list; `ContextCompat.startForegroundService` from
    the receiver. Android 15's ~6h/24h dataSync budget is accepted for v1 (cap
    single recordings at 6h; noted as a `specialUse` escape hatch if it bites).

## Phase A — the engine

### A1. New `android/.../recording/LiveRecordingService.kt`

Foreground service (`dataSync`), actions START / STOP / STOP_ALL /
SCHEDULED_START. Per-task `RecordingState` (taskId, url, headers, fileName,
channelName, startedAtMs, endAtMs limit, bytes, uri, AtomicBoolean
running/finished). Worker thread per task:

- Create MediaStore pending row up front; open "rw" descriptor.
- HTTP GET with channel headers; NO Range (live streams don't resume; a
  reconnect after a drop just keeps appending — TS tolerates the discontinuity).
- 256 KB copy loop; bytes counter; stop flag checked per read; duration cap
  checked per read; `lastByteAt` for the stall watchdog (60s silence → close
  stream → reconnect attempt, max 3 consecutive dead reconnects → finalize).
- Finalize: flush, fsync, clear IS_PENDING (row with 0 bytes → delete instead),
  persist terminal entry for Dart pickup, notification "Recording saved" /
  "Recording failed", `RecordingBridge.emit` event.
- `RecordingRegistry` (in-process, mirrors `DownloadRegistry`): live bytes +
  startedAt + channel info, readable by both activities without binding; also a
  main-thread listener list so player UIs can repaint REC state on change.

### A2. `RecordingTaskStore.kt` (same package)

Persisted JSON map (prefs `debrify_recording_service`), entries: taskId, url,
headers, fileName, channelName, uri, status (recording/done/failed), bytes-at-
last-persist, startedAtMs, endAtMs, updatedAt. On service (re)start and on
`queryLiveRecordings`, any entry status=recording with no live worker = process
died mid-recording → finalize its row (clear IS_PENDING; it holds real bytes),
flip to done. That is the whole crash story: the bytes already live in the
destination file, so death loses at most the unflushed tail.

### A3. `MainActivity` channel methods (existing `com.debrify.app/downloader`)

- `startLiveRecording{url, headers, fileName, channelName, maxDurationMs?}` →
  taskId or `fgs_not_allowed` / `engine_unsupported` (<Q).
- `stopLiveRecording{taskId}` / `stopAllLiveRecordings`.
- `queryLiveRecordings` → list incl. live bytes (mirrors `queryDownloadTasks`),
  reconciling dead entries first.
- `forgetLiveRecording{taskId}` (Dart consumed a terminal state).

### A4. Dart `lib/services/live_recording_service.dart`

Thin static wrapper over the channel methods (AndroidNativeDownloader style),
plus `recordingEngineEnabled()` (shared_preferences read, default true) and the
Q+ probe reuse (`AndroidNativeDownloader.canPublishRecordings`).

### A5. Dart player wiring (`video_player_screen.dart`)

`_toggleRecording` on Android + flag ON: probe `file-format`; progressive →
`LiveRecordingService.start(url: _playingIptvUrl, headers:
channel.playbackHeaders, ...)`, track returned taskId in `_engineRecordingTaskId`;
Stop → engine stop. Segmented → existing tee path unchanged. Engine recordings:
NO auto-stop in `_switchToIptvChannel` / `_tryOpenLiveStream` / lifecycle
onPause / dispose (those remain tee-only), REC chip stays only while the
recorded channel is the current one; a small persistent "REC" pill (Phase B)
shows whenever any engine recording is live.

### A6. Native TV player wiring (`AndroidTvTorrentPlayerActivity.kt`)

`recordingEngineEnabled()` read from FlutterSharedPreferences (default true).
`toggleIptvRecording()`: engine path starts/stops `LiveRecordingService` with
currentIptvStreamUrl/currentIptvHttpHeaders/entry.name; button state asks
`RecordingRegistry` whether THIS url is being recorded; `updateRecordButtonState`
subscribes to registry changes. Auto-stop calls short-circuit when the flag is
ON. Tee path untouched for flag OFF.

## Phase B — independent-recording UX

- Notification per recording: channel name, elapsed (h:mm:ss from startedAtMs),
  size (fmtBytes), Stop action (PendingIntent ACTION_STOP, IMMUTABLE), its own
  "Recordings" channel (`recordings_channel_v1`, IMPORTANCE_LOW), updated every
  ~2s by a time-throttle in the worker loop. Summary notification mirrors the
  downloads one ("2 recording").
- Players: the Record button is the in-player surface — it shows "Stop" when the
  CURRENTLY PLAYING url (or its Xtream twin) has a live engine task, restored on
  player open / channel change via `queryLiveRecordings` + the in-process
  registry listener on TV. The notification is the global surface for
  recordings of channels you're no longer watching. (A standalone REC pill was
  considered and dropped: two surfaces that can disagree beat one honest button
  plus the notification.)
- Cap: 2 concurrent engine recordings (`recording_limit_reached` → toast from
  players; a scheduled start that hits the cap posts a "Scheduled recording
  skipped — recording limit" notification instead, since no UI exists then).
- Recording continues across: zap, source switch, player exit, Home, app swipe-
  kill (started foreground services survive task removal), device sleep
  (wake+wifi locks — same as downloads).
- Manual recordings carry the same 6h `maxDurationMs` safety cap as scheduled
  ones; hitting a cap finalizes CLEANLY as done ("Recording saved (6h limit)"),
  never as failed.

## Phase C — scheduled recordings

### C1. `RecordingScheduleStore.kt`

Prefs JSON map id → {channelName, url, headers, startMs, endMs, programmeTitle,
sourceLabel, createdAt}. CRUD synchronized; ids are epoch-millis strings.

### C2. `RecordingAlarmReceiver.kt` + `RecordingBootReceiver.kt`

- Alarm extra = scheduleId. On fire: load entry; delete it FIRST (one-shot —
  fired is fired, success or not); if now < endMs - 60s, build START intent
  (taskId = scheduleId, fileName from programme+channel+timestamp,
  maxDurationMs = endMs - now + 2 min pad) and
  `ContextCompat.startForegroundService`. If the start throws (an OEM ignoring
  the alarm exemption), post a plain "Scheduled recording couldn't start"
  notification directly from the receiver — silent loss is the one outcome that
  is never acceptable. If already past end, the delete alone was right (missed).
- taskId = scheduleId also makes double-delivery safe: the service's
  duplicate-START guard turns the second delivery into a no-op.
- Registration helper (companion): `registerAll(context)` — for each stored
  schedule in the future → `setExactAndAllowWhileIdle` (or `setWindow` fallback
  when `canScheduleExactAlarms()` is false on 12/13+ without the grant);
  schedules already inside their window (late-join: device was off/rebooted at
  start time) → an exact alarm ~5s out, NOT a direct service start; schedules
  fully past → drop.
  Why the 5s alarm: Android 15 forbids starting a dataSync FGS from a
  BOOT_COMPLETED receiver, and the alarm-fire path carries its own
  background-start exemption on every version — one uniform, legal path for
  scheduled starts no matter who noticed the schedule.
- Boot receiver (RECEIVE_BOOT_COMPLETED) → `registerAll`. MainActivity engine
  setup also calls `registerAll` once per process (belt-and-braces for OEMs that
  drop alarms, and the path that revives schedules after a force-stop — a
  force-stopped app gets no alarms and no boot broadcast until the user next
  opens it; accepted platform gap, the reopen late-joins).

### C3. Manifest

`SCHEDULE_EXACT_ALARM` + `USE_EXACT_ALARM` + `RECEIVE_BOOT_COMPLETED`
permissions; `LiveRecordingService` (dataSync); both receivers with
`exported=false` — settled: `android:exported` only controls NON-system senders,
so protected system broadcasts (BOOT_COMPLETED) and same-app PendingIntents
(alarms) both reach a non-exported receiver.

### C4. Channel methods + Dart service

`scheduleRecording{...}` (validates: future end, non-Stremio url, exact-alarm
availability returned), `cancelScheduledRecording{id}`,
`listScheduledRecordings`, `exactAlarmState` → granted|degraded,
`openExactAlarmSettings` (ACTION_REQUEST_SCHEDULE_EXACT_ALARM, 12+).

### C5. Dart UI

- `EpgScheduleList` (+`_ScheduleRow`) gains `onRecordProgramme`: tapping/OK on a
  FUTURE programme (currently inert, like past-without-archive rows) opens a
  confirm dialog "Record <title>? <time range>" → schedule. Wired from
  `iptv_channel_sheet.dart` (both panes) where the `IptvChannel` context (url,
  playbackHeaders, name) lives; offered only when flag ON, Android Q+, url not
  Stremio, and url progressive-or-Xtream-rewritable. Warn (don't dup) when the
  same url+startMs is already scheduled.
- Native TV guide (`IptvEpgAdapter`): click on a FUTURE programme (currently
  inert) → confirm dialog → `RecordingScheduleStore.add` + `registerAll`
  directly in Kotlin (no bridge round-trip needed); same gates.
- IPTV settings: new "Recording" section in BOTH `iptv_settings_page.dart` and
  the TV two-pane variant if it carries its own tile list — engine toggle,
  "Scheduled recordings" page (list upcoming with channel/programme/time,
  cancel on tap/OK), exact-alarm warning row when degraded, all with existing
  focusable settings idioms + settings-search entries.

## Risk / correctness notes

- **Connection limits:** second connection on same-channel record; Xtream
  `max_connections=1` accounts may drop playback or refuse the recording.
  Documented; copy says "uses an extra connection".
- **Xtream URL snapshots** may expire for scheduled recordings on rotating-token
  panels; v1 accepts (fails with a "couldn't start" notification).
- **Android 15 dataSync budget** (~6h/24h): single-recording cap 6h; noted.
- **Doze:** `setExactAndAllowWhileIdle` fires in Doze; the FGS + wake locks keep
  the pump alive. OEM killers remain the wild card (battery-optimization
  exemption plumbing already exists app-side).
- **Time changes:** alarms are epoch-based (RTC_WAKEUP); TIME_SET/TIMEZONE re-
  registration deferred (accepted gap, listed in plan).
- **Duplicate schedule fire vs late-join:** `registerAll` start-immediately path
  and the alarm both call START with taskId = scheduleId; the service's
  duplicate-START guard (same live task) makes the second a no-op.
- **Extension-less URLs on the Dart engine path:** mpv's `file-format` probe is
  ground truth for what's playing; anything not clearly segmented records as raw
  bytes — exactly what mpv itself received.

## Files touched

New: `recording/LiveRecordingService.kt`, `recording/RecordingTaskStore.kt`,
`recording/RecordingRegistry.kt` (may live inside the store file),
`recording/RecordingScheduleStore.kt`, `recording/RecordingAlarmReceiver.kt`,
`recording/RecordingBootReceiver.kt`, `lib/services/live_recording_service.dart`,
`lib/screens/settings/scheduled_recordings_page.dart`.

Modified: `AndroidManifest.xml`, `MainActivity.kt` (channel methods + engine
`registerAll`), `AndroidTvTorrentPlayerActivity.kt` (engine routing + guide
record + REC pill), `video_player_screen.dart` (engine routing + REC pill),
`iptv_epg_panel.dart` (+record affordance), `iptv_channel_sheet.dart` (wiring),
`iptv_settings_page.dart` (+section), `settings_search.dart` (index entries),
`live` layout xml only if the REC pill needs a native view (prefer reusing the
record button's text/color states first).

## Test checklist (device)

1. TV: record progressive channel → zap around, open other screens, press Home,
   relaunch → recording still running (notification), Stop → file in
   Downloads/Debrify/Recordings, plays.
2. Phone: record progressive channel → leave player → REC pill/notification →
   stop from notification.
3. Phone: record HLS channel → tee path banner ("stops if you leave") →
   behaves exactly as pre-engine build.
4. Kill app mid-engine-recording → relaunch → partial recording finalized and
   visible.
5. Schedule a programme 2 min out → close app → recording starts at time, stops
   at end+pad, file plays. Repeat with device rebooted between schedule and
   fire. Repeat with device asleep.
6. Schedule while 2 recordings active → third refused with clear message.
7. Flag OFF → everything behaves as the tee build; scheduling UI hidden.
8. Android 12 device/emulator: exact alarm works without any prompt.

## Plan review notes (2 passes, fixes applied above)

Pass 1 (lifecycle / platform rules): settled `exported=false` for both
receivers; boot receiver must NEVER start the FGS directly (Android 15 blocks
dataSync FGS from BOOT_COMPLETED) → late-join always goes through a ~5s exact
alarm, whose fire carries the background-start exemption on every version;
force-stop kills alarms until next app open (accepted, revived by the
MainActivity registerAll); alarm PendingIntents FLAG_IMMUTABLE, requestCode =
scheduleId hash; schedule entry deleted BEFORE the start attempt with a failure
notification as the no-silent-loss backstop; taskId = scheduleId makes
double-delivery a no-op; dead "recording" store entries are finalized (never
resumed — a live capture has an unbounded gap after death).

Pass 2 (UX / integration): tee auto-stop call sites left byte-for-byte alone on
both players (idle no-ops; engine state invisible to them); dropped the REC
pill in favor of honest-button + notification; cap-hit on the scheduled path is
a notification, not a toast; added the Xtream `.m3u8→.ts` rewrite (major
coverage win for engine + scheduling, incl. enabling Record on Xtream-HLS
channels in the native player); mpv `file-format` probe with URL-heuristic
fallback, ambiguity → tee; duplicate-schedule warning by url+startMs; manual
recordings share the 6h cap and caps finalize as done, not failed; settings
section must cover the TV two-pane variant too.
