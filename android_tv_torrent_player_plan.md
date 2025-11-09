# Android TV Torrent Player Plan

## Context & Goals
- Build a brand-new ExoPlayer-based Android TV experience for torrent playback flows (single file, video collection, series) without reusing the existing Debrify TV player (`TorboxTvPlayerActivity`).
- Mirror the Flutter player logic from `lib/screens/video_player_screen.dart` (~4.2k LOC) for detection, resume state, and playlist/series handling, but tailored to Android TV UI/UX.
- Reuse existing data models & persistence from `StorageService` to keep resume data, playback states, and track preferences consistent across platforms.
- Ensure the Flutter torrent pages can launch this activity seamlessly through `AndroidTvPlayerBridge`, passing enough metadata to recreate the experience natively and receiving progress updates.

## Current Building Blocks
- **Detection logic**: Flutter already distinguishes single vs collection vs series when preparing playback (see `PlaylistEntry`, `SeriesPlaylist`, `EpisodeInfoService`, etc.). We will call this before launching the TV activity and include the classified payload in the intent.
- **Resume storage**: `StorageService.getVideoPlaybackState`, `saveVideoPlaybackState`, `getSeriesPlaybackState`, `saveSeriesPlaybackState`, and `upsertVideoResume` hold timestamps, playlist indices, seasons/episodes, etc. Data contract must remain identical.
- **Bridge**: `lib/services/android_tv_player_bridge.dart` exposes `launchRealDebridPlayback` / `launchTorboxPlayback`, hooking to `MainActivity.handleLaunchTvPlayback`, which starts `TorboxTvPlayerActivity`. We'll extend this with new methods/payloads for the torrent player and add callbacks for progress reporting.
- **Native UI reference**: `android/app/src/main/java/com/debrify/app/tv/TorboxTvPlayerActivity.java` already handles complex ExoPlayer UI, focus management, overlays, and method-channel callbacks. We'll use it as inspiration but not share code.

## High-Level Architecture
1. **Flutter layer**
   - Detect playback type when a torrent search result is launched.
   - Gather resume info using `StorageService` based on content type.
   - Build a serializable payload describing:
     - Content type (`single`, `collection`, `series`).
     - Media list (urls, titles, IDs, torrent/hash info, track prefs).
     - Resume data (timestamp, active index, season/episode, completion flags).
     - UI metadata (posters, season art, synopsis, tvmaze mapping results).
   - Invoke a new bridge method `launchAndroidTvTorrentPlayback(...)` passing the payload.
   - Expose callbacks for:
     - `requestNextStream` (if user triggers next file).
     - `requestEpisodeList` / `requestCollectionDetails` (if necessary).
     - `onPlaybackProgress` (native -> Flutter) carrying updated resume state for saving via `StorageService`.

2. **Bridge updates (`android_tv_player_bridge.dart`)**
   - Add method to invoke new channel method (e.g., `launchTorrentPlayback`).
   - Register callbacks for progress updates using `MethodChannel.setMethodCallHandler` (cases like `torrentPlaybackProgress`, `torrentPlaybackFinished`).
   - Ensure cleanup mirrors existing Torbox bridge behavior.

3. **Android native layer**
   - **Activity**: create `AndroidTvTorrentPlayerActivity` under `com.debrify.app.tv`.
     - Accept intent extras: serialized playlist/series data (use `Bundle`/`Parcelable`).
     - Initialize ExoPlayer (Media3) with per-item configs.
     - Render custom controls for:
       - Playback (play/pause, seek ±10s, speed, aspect ratios).
       - Collection navigator (grid/list of files with thumbnails, focus-friendly).
       - Series browser (season list + episode cards using tvmaze metadata and progress badges).
     - Show resume badges and start positions per payload.
     - Continuously emit progress via channel back to Flutter (throttle: e.g., every 5 seconds + on state changes).
     - Save last-known playback on stop/destroy.
   - **UI Components**:
     - Card rows (RecyclerView + leanback focus) for episodes/collections.
     - Seekbar overlay similar to Flutter gestures but optimized for D-pad.
     - Subtitle/audio selection using Media3 track APIs.
   - **Data handling**:
     - Map incoming JSON -> Kotlin models.
     - Manage active playlist index, handle completion -> auto-next (within collection or series).
     - When hitting end-of-list, notify Flutter (so it can mark complete or fetch next season?).
   - **Method channel callbacks**:
     - Reuse `MainActivity` channel; add `launchTorrentPlayback` handler launching new activity.
     - Provide static helper to send progress events back (via the same channel or `EventChannel`).

## Detailed Implementation Steps
1. **Define payload schema**
   - Draft Dart models/DTOs (e.g., `AndroidTvPlaybackPayload`) capturing everything the native side needs.
   - Include:
     - `contentType`: enum.
     - `items`: list of `PlaybackItem` objects (url, title, duration?, poster, ids).
     - `seriesMeta`: optional structure with `seriesTitle`, `seasonList`, `tvmazeIds`, episode numbers, descriptive text.
     - `resume`: object with `positionMs`, `itemIndex`, `season`, `episode`, `playedSeconds`, `wasCompleted`.
     - `userPreferences`: audio/subtitle track IDs if stored via `StorageService`.
   - Document the schema in both Dart and Kotlin to avoid drift.

2. **Flutter integration**
   - In torrent playback entry point (where `VideoPlayerScreen` would be pushed), add Android-TV detection and call the bridge instead.
   - Reuse existing logic for:
     - Determining `SeriesPlaylist` vs `PlaylistEntry`.
     - Fetching `StorageService` resume states & track prefs.
     - Writing progress updates (when receiving from native, call `StorageService.save*`).
   - Ensure fallback to Flutter player still works on non-TV devices or if bridge launch fails.

3. **Bridge enhancements**
   - Add method `launchTorrentPlayback({required AndroidTvPlaybackPayload payload, ...})` that:
     - Calls `_ensureInitialized()`.
     - Sets progress callback references.
     - Invokes `MethodChannel('launchTorrentPlayback', payload.toMap())`.
   - Extend `_channel.setMethodCallHandler` cases for:
     - `torrentPlaybackProgress` (arguments: payload map). Call a new Dart callback that saves via `StorageService`.
     - `requestTorrentNext` if the native player needs Flutter to resolve another file (e.g., remote playlist update).
     - `torrentPlaybackFinished` for cleanup.

4. **MainActivity updates**
   - Add `launchTorrentPlayback` case mirroring existing handlers but targeting `AndroidTvTorrentPlayerActivity`.
   - Pass the serialized payload extras (consider using `Intent.putExtra("payload", JSONObject)`). For large structures, use `Bundle`/`Serializable` or temporary file.

5. **New Android TV activity**
   - **Player setup**:
     - Initialize `ExoPlayer` with `DefaultTrackSelector`, `DefaultLoadControl` tuned for VOD.
     - Build `MediaItem`s from playlist entries (set metadata, artwork, season/episode numbers via `MediaMetadata.Builder`).
   - **Resume handling**:
     - On start, read resume info and seek before playback.
     - For series/collection, highlight the saved item in the UI and auto-scroll to it.
   - **UI/UX**:
     - Layout includes PlayerView, overlay controls, info banner, and optional card panel triggered via D-pad Up/Menu.
     - Build episode/collection cards using `RecyclerView` + `GridLayoutManager` (horizontal row per season or aggregated list).
     - Display progress indicators on cards (e.g., thin bars or “Resume 42m”).
   - **D-pad interactions**:
     - Left/Right for seeking ±10s.
     - Up to open cards/metadata.
     - Down to show playback controls (play/pause, audio, subs, speed, aspect).
     - Long-press OK for “Next item”.
   - **Progress reporting**:
     - On position change, build progress map containing `contentType`, `itemId`, `positionMs`, `durationMs`, `season`, `episode`, `completed`.
     - Throttle events and send via `MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("torrentPlaybackProgress", map)`.
     - On completion or stop, send final event + `torrentPlaybackFinished`.
   - **Episode mapping**:
     - Use passed-in tvmaze metadata to render cards. No network fetch on TV side; Flutter already resolved the mapping.

6. **Persistence logic duplication**
   - When Flutter receives `torrentPlaybackProgress`, call existing `StorageService.saveVideoPlaybackState` / `saveSeriesPlaybackState` / `upsertVideoResume` with the same shapes as the Flutter player uses.
   - Ensure the keys (e.g., `series_<slug>`, `video_<slug>`, resume keys) match so resuming works cross-platform.

7. **Error handling & fallbacks**
   - If native launch fails, clean up bridge callbacks and fall back to Flutter `VideoPlayerScreen`.
   - Handle network failures or missing URLs by notifying Flutter via a `torrentPlaybackError` callback so it can show a toast and maybe open the Flutter player.

8. **Testing strategy**
   - **Unit**: Dart-side payload builders & callback handlers (mock StorageService to verify saves).
   - **Instrumentation**: Android TV emulator/manual tests for single video, collection, series flows.
   - **Integration**: Verify progress syncing by starting playback on TV, stopping mid-way, then reopening on mobile (should resume).
   - **Edge cases**: missing resume data, partial metadata, audio/subtitle preference absence, long collections (>100 items), tvmaze mismatches.

## Open Questions / Follow-Ups
- Exact UI spec for the “beautiful card” layout on TV (animations, focus order). Need confirmation or mockups.
- Should the TV activity support Real-Debrid/Torbox switching mid-play (like Debrify TV) or strictly torrent playback from the Flutter UI? Current scope assumes the latter.
- Do we need DRM/license support for any providers? (Affects MediaItem configuration.)
- Preferred persistence frequency for progress events (every X seconds vs. state changes only).

## Estimated Effort Breakdown
1. Schema & Flutter payload plumbing: 0.5–1 day.
2. Bridge & MainActivity wiring: 0.5 day.
3. Android TV activity (UI, ExoPlayer, playlist logic): 2–3 days.
4. Progress callbacks & StorageService integration: 0.5 day.
5. Testing & polish: 1 day.

**Total**: ~4–5 developer-days, assuming existing metadata models are reused and no brand-new design assets are required.
