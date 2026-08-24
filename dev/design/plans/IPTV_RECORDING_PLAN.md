# IPTV Recording — Implementation Plan

Add a **Record** control for live IPTV in both players:

- **Dart / media_kit (libmpv)** player — phones + desktop. Uses libmpv's native
  `stream-record` property. Works for both progressive and HLS live streams
  (libmpv muxes whatever it's playing).
- **Native Android TV / ExoPlayer** player — uses a teeing `DataSource` that
  copies the bytes ExoPlayer already reads into a file. Enabled for **direct /
  progressive** live streams only; **disabled (greyed) for HLS (`.m3u8`)**, per
  the agreed scope.

Recording is **"record from now"** (live edge forward), not timeshift.

---

## Scope / non-goals (v1)

- Only **live** IPTV channels expose the button (`isLive == true`). VOD/series
  already have a full seekbar and are downloadable elsewhere.
- Native TV: **progressive only**. HLS shows the button **disabled**.
- Output container: **MPEG-TS (`.ts`)** — the natural container for live TS and
  what libmpv/`stream-record` produces cleanly for these streams.
- No pause/resume of a recording, no scheduled/EPG-based recording, no ring
  buffer / "record last N minutes".
- Recording stops automatically on channel change, player exit, or (native) an
  HLS-fallback that invalidates the progressive assumption.

---

## Storage (mirrors the app's existing MediaStore idiom)

The app is fully scoped-storage / MediaStore based (`MediaStoreDownloadService.createViaMediaStore`),
`MediaStore.Downloads`, `RELATIVE_PATH = "Download/Debrify"`, `IS_PENDING` toggle,
no `WRITE_EXTERNAL_STORAGE`. Recordings go to **`Download/Debrify/Recordings`**.

| Platform / player | How the file is written | Made user-visible |
| --- | --- | --- |
| Native TV (ExoPlayer) | Tee writes straight into a `MediaStore.Downloads` **pending** row's fd; clear `IS_PENDING` on stop | Direct — no copy |
| Android phone (libmpv) | libmpv needs a filesystem path → record to app-external dir, then a **new** native `saveFileToMediaStore` copies it into `Download/Debrify/Recordings` and deletes the temp | Copy on stop |
| Desktop (libmpv) | Record straight into `<Downloads>/Debrify/Recordings` (reuse `DownloadService.getDownloadsRoot()` idiom) | Direct |

---

## Part A — Dart / media_kit (phones + desktop)

### A1. `lib/screens/video_player/widgets/controls.dart`
- Add 3 fields + constructor params: `final bool hasRecord`, `final bool isRecording`, `final VoidCallback? onRecord` (mirror `hasIptvChannels` / `onShowIptvChannels`).
- Add a `NetflixControlButton` in the bottom Row (`:365-488`), guarded by
  `if (hasRecord && onRecord != null)`:
  - not recording → `icon: Icons.fiber_manual_record, label: 'Record'`
  - recording → `icon: Icons.stop_circle_rounded, label: 'Stop'`

### A2. `lib/screens/video_player_screen.dart`
- New state: `bool _isRecording = false;`, `String? _recordingTempPath;`,
  `bool _recordingSupported = false;`.
- After `_player` is created (`:1607`), set
  `_recordingSupported = _player.platform is mk.NativePlayer;` (false on web).
- `bool get _canRecord => _recordingSupported && _iptvZapBannerOwnsIdentity;`
  (live IPTV only — `_iptvZapBannerOwnsIdentity` is the existing live flag).
- Wire into the `Controls(...)` build site (`:7884+`):
  `hasRecord: _canRecord, isRecording: _isRecording, onRecord: _canRecord ? _toggleRecording : null`.
- `_toggleRecording()`:
  - if `_isRecording` → `_stopRecording()`
  - else → `_startRecording()`
- `_startRecording()`:
  - `final platform = _player.platform; if (platform is! mk.NativePlayer) return;`
  - compute temp path via `_recordingTargetPath()`, ensure parent dir exists.
  - `await platform.setProperty('stream-record', path);`
  - `setState(() { _isRecording = true; _recordingTempPath = path; });`
  - SnackBar "Recording started".
- `_stopRecording()`:
  - `await platform.setProperty('stream-record', '');` (empty = stop/flush)
  - Android → `AndroidNativeDownloader.saveLocalFile(...)` to publish + delete temp; SnackBar with location. Desktop → SnackBar with the saved path.
  - `setState(() { _isRecording = false; _recordingTempPath = null; });`
- `_recordingTargetPath()`:
  - filename: `<sanitized channel name>_<yyyyMMdd_HHmmss>.ts`
  - dir: Android → `getExternalStorageDirectory()/Debrify/Recordings`;
    desktop → `DownloadService.getDownloadsRoot()/Recordings`;
    fallback → `getApplicationDocumentsDirectory()/recordings`.
- **Auto-stop**: call `_stopRecording()` (best-effort, no UI) before an IPTV
  channel switch (in the existing zap/channel-change path) and in `dispose()`.

### A3. `lib/services/android_native_downloader.dart`
- Add `static Future<String?> saveLocalFile({ required String path, required String fileName, String subDir = 'Debrify/Recordings', String mimeType = 'video/mp2t' })`
  → `invokeMethod('saveFileToMediaStore', {...})`; returns the content URI string or null.

### A4. `android/app/src/main/kotlin/com/debrify/app/MainActivity.kt`
- Add a `"saveFileToMediaStore"` branch to the existing
  `com.debrify.app/downloader` MethodChannel handler (`:579+`): insert a
  `MediaStore.Downloads` pending row (`Download/<subDir>`), copy the temp file
  in, clear `IS_PENDING`, delete the temp, `result.success(uri)`. Runs on a
  background thread (small helper), posts result to main. Mirrors
  `MediaStoreDownloadService.createViaMediaStore` exactly.

---

## Part B — Native Android TV / ExoPlayer

### B1. New file `android/.../tv/IptvRecordingController.kt`
Thread-safe controller owning the destination stream + state:
- `start(streamUrl, displayName, mimeType): Boolean` — insert MediaStore pending
  row (`Download/Debrify/Recordings`), open `"rw"` fd → `BufferedOutputStream`,
  set `active`, remember `targetUri = Uri.parse(streamUrl)`.
- `shouldRecord(uri): Boolean` — `active && uri.toString() == targetUri.toString()`.
- `write(buf, off, len)` — synchronized; write to stream; count bytes; on
  `IOException` abort cleanly.
- `stop(): Uri?` — flush/close, clear `IS_PENDING`, return content uri.
- `abortAndDelete()` — close + `contentResolver.delete(row)` (for HLS-fallback /
  error, where the partial file is unusable).
- All mutations guarded by a single lock; `active` is `@Volatile` for the
  read-hot `shouldRecord`.

### B2. New file `android/.../tv/RecordingDataSource.kt`
- `RecordingDataSource(upstream: DataSource, controller: IptvRecordingController) : DataSource`
  — delegates every method to `upstream`; in
  `read(buffer, offset, length)`: `val n = upstream.read(...); if (n > 0 && controller.shouldRecord(uri)) controller.write(buffer, offset, n); return n`.
  Caches `uri` from `open()`.
- Nested `Factory(upstreamFactory, controller) : DataSource.Factory`.
- Implements the `androidx.media3.datasource.DataSource` interface directly
  (delegating `addTransferListener`, `open`, `getUri`, `getResponseHeaders`,
  `close`) — no dependency on `ForwardingDataSource` existing in 1.8.0.

### B3. `AndroidTvTorrentPlayerActivity.kt` wiring
- Field: `private val iptvRecordingController by lazy { IptvRecordingController(this) }`,
  `private var iptvRecordButton: AppCompatButton? = null`.
- `setupPlayer` (`:1210-1229`): wrap the IPTV factory —
  `val recordFactory = if (isIptvMode) RecordingDataSource.Factory(finalDataSourceFactory, iptvRecordingController) else finalDataSourceFactory`
  and feed `recordFactory` into `DefaultMediaSourceFactory`.
- Init button (`:1890` area): `iptvRecordButton = playerView.findViewById(R.id.iptv_record_button)`.
- `setupIptvControls` (`:5507`): include `iptvRecordButton` in the premium-style
  list; set click → `toggleIptvRecording()`.
- Visibility/enabled: in `updateIptvControlPresentation` / live-dock arrange —
  show only when `entry.isLive`; `isEnabled = !isCurrentIptvHls()`; when disabled,
  dim (`alpha = 0.4`) + label "Record (HLS n/a)" is out of scope, keep "Record"
  but dimmed & non-focusable-clickable.
- `isCurrentIptvHls()`: `val u = currentIptvStreamUrl; u == null || u.substringBefore('?').endsWith(".m3u8", true) || iptvHlsForcedUrls.contains(u)`.
- `toggleIptvRecording()`:
  - if `iptvRecordingController.isActive` → `stop()` + Toast "Saved to Downloads/Debrify" + restyle button to idle.
  - else → guard HLS (defensive); `start(currentIptvStreamUrl!, channelName, "video/mp2t")`; Toast "Recording…"; restyle button to REC (red).
- **Auto-stop hooks**:
  - `setIptvMediaItem` / channel zap: if active and the new stream URL differs,
    `stop()` first (finalizes the recording for the previous channel).
  - `retryIptvAsHlsIfUnrecognized`: if active, `abortAndDelete()` + Toast
    "Recording stopped (stream is HLS)"; then disable the button.
  - `onStop()` / `onDestroy()`: `stop()` to avoid a dangling pending row.
- REC indicator: restyle the button itself (red drawable tint + text "STOP")
  while active — avoids adding a new always-on overlay view (lower layout risk).

### B4. `res/layout/view_torrent_tv_controls.xml`
- Add an `AppCompatButton` `@+id/iptv_record_button` mirroring
  `iptv_jump_channel_button` (`:248-254`): `style="@style/CinemaControlButton"`,
  `android:drawableStart="@drawable/ic_record"`, `android:text="Record"`,
  `android:visibility="gone"`.

### B5. `res/drawable/ic_record.xml`
- New 24dp vector: a red filled circle (record glyph).

---

## Risk / correctness notes

1. **libmpv `stream-record`** is a runtime-settable property (mpv ≥ 0.30);
   media_kit_libs bundles a recent libmpv. Empty string stops. Records from the
   current position → "record from now".
2. **Tee only the main stream**: `shouldRecord` matches the dataSpec URI to the
   channel URL, so subtitle/keys/other requests through the same factory are not
   captured. Progressive live opens exactly one continuous DataSource; a network
   re-open reuses the same URL and appends to the same file (small gap tolerated).
3. **Mid-stream start on TS is valid** (decoders join at PAT/PMT). Progressive
   MP4 would be unplayable if started mid-file, but live IPTV progressive is
   essentially always MPEG-TS; VOD (seekable MP4) never shows the button.
4. **HLS on native** intentionally disabled — a naive tee of playlist+segments is
   garbage; libmpv path still records HLS fine on phones/desktop.
5. **No `WRITE_EXTERNAL_STORAGE` needed** — MediaStore on API 29+. Matches the
   app's existing storage model.
6. **Cannot run Android/Flutter build in this environment** — no `flutter`
   toolchain available. Verification is by careful static review against the
   exact APIs and existing call sites cited above. This will be called out in the
   handoff so it can be built/tested on a device.

---

## Files touched

**New**
- `android/app/src/main/kotlin/com/debrify/app/tv/IptvRecordingController.kt`
- `android/app/src/main/kotlin/com/debrify/app/tv/RecordingDataSource.kt`
- `android/app/src/main/res/drawable/ic_record.xml`

**Edited**
- `lib/screens/video_player/widgets/controls.dart`
- `lib/screens/video_player_screen.dart`
- `lib/services/android_native_downloader.dart`
- `android/app/src/main/kotlin/com/debrify/app/MainActivity.kt`
- `android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`
- `android/app/src/main/res/layout/view_torrent_tv_controls.xml`

---

## Plan review notes (2 passes)

**Pass 1 — API/correctness (verified against the tree):**
- media3 datasource classes are `@UnstableApi`; the project opts in per-file with
  `@androidx.annotation.OptIn(UnstableApi::class)` (see AndroidTvTorrentPlayerActivity
  `:92`). → `RecordingDataSource.kt` must carry that annotation; `IptvRecordingController.kt`
  touches only MediaStore, so it does not.
- `RecordingDataSource.read` delegates `upstream.read(buffer, offset, length): Int`
  and tees when `>0`; cache the **`dataSpec.uri` from `open()`** (not `upstream.getUri()`,
  which is post-redirect) for `shouldRecord` matching against the channel URL.
- Live dock is rebuilt by `arrangeLiveIptvControlDock()` (`:5590`) via
  `replaceControlDockOrder`; the record button must be added to that `desired`
  list, the `setupIptvControls` style list, and `updateIptvControlPresentation`
  visibility — otherwise it won't appear/position in the live dock.
- Dart channel switch funnels through `_switchToIptvChannel(index)` (`:4045`) →
  auto-stop hook goes at its top; `_zapIptvChannel` routes through it.

**Pass 2 — edge cases / risk trims:**
- `saveFileToMediaStore` copy runs on a **background thread** in MainActivity; the
  MethodChannel `result` is posted back on the main thread (large copy must not ANR).
- Dart `_stopRecording` stops libmpv synchronously (`stream-record`→"") but runs the
  Android MediaStore publish **fire-and-forget** so a channel switch isn't blocked by
  a multi-GB copy; the "saved" SnackBar fires on publish completion.
- Native: bare-URL HLS channels can't be known-HLS until the first failed sniff;
  the `retryIptvAsHlsIfUnrecognized` hook `abortAndDelete()`s the partial and
  disables the button, so at worst a few unusable KB are written then removed.
- REC state is shown by restyling the existing button (red tint + "STOP"), not a
  new always-on overlay view → minimal layout/focus risk.
- Everything best-effort/guarded: a recording failure must never crash playback.

**Build caveat:** no `flutter`/Android toolchain in this environment, so the code is
written by static review against the exact APIs/call-sites above and cannot be
compiler-verified here — must be built/tested on a device. Called out in the handoff.
