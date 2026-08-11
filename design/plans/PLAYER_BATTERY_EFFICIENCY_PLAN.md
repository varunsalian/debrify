# Player battery and thermal efficiency — all-device plan

Status: **Phase 0 runtime decoder diagnostics and Phase 1 UI isolation are
implemented. On the OnePlus CPH2573, the Android renderer experiment measured
about 62% process CPU for Automatic, 51% for Direct MediaCodec, and 45% for
Direct Surface on the same 1080p H.264 stream. Direct Surface is now the
phone/tablet default by product decision, with an explicit Automatic
compatibility fallback. A confirmed pre-first-frame MediaCodec/surface failure
now disposes the Direct Surface player, recreates it in Automatic mode, restores
the session, and persists Automatic for later playback. Broader device/codec
validation remains outstanding.**

This plan covers Android phones/tablets, Android TV, iPhone/iPad, tvOS,
macOS, Windows, Linux, and web. It deliberately does not prescribe one decoder
setting for every platform: the current playback backends and the efficient
native output paths are different on each platform.

The first release should contain the shared Flutter UI fix and better
measurement. Renderer or backend changes ship only when their own device gate
passes. The existing media-kit path remains the rollback path until a replacement
has proved the full Debrify feature contract.

---

## What is known now

| Platform | Current Debrify path | Confirmed or likely state | First action |
|---|---|---|---|
| Android phone/tablet | media-kit/libmpv -> Flutter `SurfaceProducer` texture | On the OnePlus CPH2573, HEVC 1080p decoded in hardware as `mediacodec-copy`; this avoids software decode but copies decoded frames back before GPU presentation | Remove Flutter rebuild waste, then compare Android renderer modes |
| Android TV | Native Media3 activities -> `PlayerView` -> `SurfaceView` | Already uses Android's preferred power-efficient surface and enables decoder fallback | Measure; do not move it back to the Flutter texture path |
| iPhone/iPad | media-kit/libmpv -> `CVPixelBuffer`/OpenGL Flutter texture | Configured with `hwdec=auto`; actual `videotoolbox` versus `videotoolbox-copy` has not been captured on a device | Capture the runtime decoder, fix shared UI work, then test direct VideoToolbox only if needed |
| tvOS | Vendored media-kit/libmpv -> `CVPixelBuffer`/OpenGL Flutter texture | Configured with `hwdec=auto`; actual decoder mode is not yet captured. The separate 4K investigation says to keep AetherEngine parked | Measure heat, CPU/GPU, dropped frames and actual decoder; retain media-kit for now |
| macOS | media-kit/libmpv texture | Expected to use VideoToolbox when supported, but runtime state must be measured | Shared UI fix plus runtime decoder/energy capture |
| Windows | media-kit/libmpv texture | Expected to use D3D11VA where supported, but runtime state must be measured | Shared UI fix plus runtime decoder/energy capture |
| Linux | media-kit/libmpv texture | VAAPI/NVDEC availability is hardware, driver and session dependent | Diagnose per machine; never globally force one Linux decoder |
| Web | media-kit web/HTML video | No native libmpv property access; browser owns decode and presentation | Shared UI fix and browser/device measurement only |

Two costs must be kept separate:

1. **Decode cost.** A configured `hwdec=auto` or `auto-safe` is only a request.
   The runtime `hwdec-current` value says what actually opened. `no` means
   software decoding; a name ending in `-copy` is hardware decode with an extra
   frame copy.
2. **Presentation/UI cost.** The current position listener updates `_position`
   and calls `setState` on the entire, very large `VideoPlayerScreen` for every
   position event. This happens even when the controls are hidden. It is common
   to all Flutter-player platforms and is independent of the decoder.

The OnePlus result proves that “every video drains because all decode is on the
CPU” is not the current explanation on that phone. It does **not** prove the
Flutter texture path is cheap.

---

## Goals and hard constraints

### Goals

- Reduce playback energy use and heat without lowering normal playback quality.
- Verify the active decoder for every media item on every native media-kit
  platform; do not infer success from configuration.
- Stop position ticks from rebuilding the full player screen.
- Preserve a reliable, per-platform fallback.
- Make every renderer decision from repeatable release-build measurements.

### Functional invariants

No optimization ships if it regresses any applicable item in this list:

- play, pause, seek, scrubbing and playback-speed changes;
- resume save/restore, completion, next episode, playlists and source switching;
- Trakt, Simkl and analytics timing semantics;
- embedded and external audio, audio-track selection and sync;
- embedded, addon and external subtitles, style, positioning and sync offset;
- HLS/IPTV/live playback, channel zapping, error recovery and recording;
- aspect ratio, crop/fit, rotation and gesture controls;
- PiP, app lifecycle, audio interruptions and route changes;
- H.264, HEVC, AV1, VP9 where supported, 8/10-bit, SDR/HDR, common containers,
  high bitrate files and multichannel audio;
- first-frame readiness, buffering UI, wakelock ownership and cleanup.

### Non-goals

- Do not disable the wakelock while someone is visibly watching.
- Do not globally force an unsafe hardware decoder.
- Do not replace Android TV's existing Media3/`SurfaceView` path.
- Do not revive the parked tvOS AetherEngine work as part of a battery fix.
- Do not build three new native players before measurement proves they are
  needed.

---

## Phase 0 — establish a reproducible baseline

Do this before changing rendering. A percentage improvement is meaningless if
brightness, radio conditions, content or thermal state changed between runs.

### 0.1 Runtime diagnostics

For every new media generation, record one privacy-safe initial line, then a
transition line if the decoder or output changes, containing:

- platform and backend family;
- codec, coded/display resolution, bit depth and HDR/SDR when available;
- `hwdec-current` and `current-vo` for native libmpv;
- dropped frames and late frames at the end of the run, when available;
- renderer/surface type for native Android;
- whether controls and subtitles were visible during the sample.

The existing `DEBRIFY_PLAYER_DECODER` release-safe line is only the starting
point. Its current `VideoParams` trigger can arrive while libmpv is still
attaching the output—the OnePlus capture demonstrated this with `output=null`.
Do not treat that as a completed diagnosis. Observe `hwdec-current` and
`current-vo`, or re-query both until they are non-empty and stable after first
frame; emit another line whenever either later changes. A mid-stream hardware
failure must not remain reported as hardware for the rest of the item.

Create the media-generation ID at every app-owned `open`/source-switch boundary;
do not depend only on media-kit emitting a zero-sized `VideoParams`, because that
is an observed behavior rather than the session contract. Keep URLs, titles,
account IDs, file names and tokens out of every line. On web, report that the
native decoder is unavailable rather than inventing a hardware verdict. Late
queries and observed-property callbacks from the previous generation are
dropped.

Capture channels:

- Android: `adb logcat` in a release APK.
- iOS/iPadOS/tvOS: unified device console or an explicit native logging bridge
  that survives release mode.
- desktop: process/system log from a release build.
- web: browser media diagnostics plus Debrify's non-native marker.

### 0.2 Fixed media suite

Use the same legally testable samples on all capable devices:

- 1080p H.264 SDR;
- 1080p HEVC SDR;
- 4K HEVC Main10 HDR and SDR;
- AV1 1080p and 4K where platform support exists;
- high-bitrate MKV with embedded subtitles and multiple audio tracks;
- HLS VOD and one representative live/IPTV stream;
- the separate-audio YouTube path.

Run subtitles off and on for at least the common 1080p case. Use a local or
fully cached source for decode/render comparisons, then separately measure Wi-Fi
and mobile streaming so network-radio power is not mistaken for renderer power.

### 0.3 Test protocol

- Release/profile builds only; debug numbers are not accepted.
- Fixed brightness, volume, resolution, refresh rate and network type.
- Start at a comparable battery level and temperature; allow a cool-down between
  runs.
- At least three 15-minute measured runs after a warm-up; use the median and
  record variance.
- Record CPU, GPU, energy/power, thermal state, dropped frames and Flutter
  build/raster activity.
- Compare Debrify with a platform-native reference using the exact same media
  only where that reference supports the container, codecs and tracks. For an
  unsupported MKV/remux, use a capable third-party reference as a directional
  comparison; never compare two different files as a numeric renderer result.

Recommended tools are Android Studio Power Profiler/Perfetto and batterystats,
Xcode Instruments Energy Log/System Trace/Metal tools, OS energy/CPU/GPU tools
on desktop, and browser media internals plus the browser task manager on web.

### Exit gate

A checked-in result sheet identifies, for each tested platform and sample:
decoder mode, output path, power/energy, CPU/GPU, thermals and dropped frames.
Any unsupported measurement is marked unknown, never assumed.

---

## Phase 1 — fix the shared Flutter position hot path

This is the lowest-risk improvement and applies to every Flutter-owned player
surface, including Apple devices and desktop. It should be completed before
judging media-kit itself.

### Design

1. Keep the raw position subscription at its current cadence for correctness.
   It continues to feed skip segments, completion checks, resume/scrobble logic
   and media-generation guards.
2. Remove the full-screen `setState` from the raw position callback.
3. Extract a small, pure `PlaybackUiClock`-style controller/notifier owned by
   the progress/time controls. It accepts raw position, visibility and gesture
   events without depending on a real media-kit player, making the cadence and
   generation rules unit-testable.
4. While controls are visible, update those leaf widgets at no more than 4 Hz.
   During an active drag/scrub, display the gesture's local target immediately.
5. When controls are hidden, stop progress/time-control notifications entirely.
   Business logic continues from the raw position. The skip-boundary detector is
   the deliberate exception because its button is designed to appear over bare
   video while the main controls are hidden.
6. Recompute skip-button visibility from the raw clock, but notify its isolated
   overlay only when the segment identity changes or the button crosses
   visible/hidden. Do not rebuild the player root for that boundary.
7. Localize duration, playing, buffering and track updates to the smallest
   dependent subtree rather than using the player-screen root as a clock.

The important distinction is **throttle UI, not playback state**. Throttling the
raw stream would create resume, completion, skip and scrobble regressions.

### Tests

- A fake 20 Hz position source causes zero root rebuilds with hidden controls.
- Visible controls receive no more than the configured UI cadence.
- Scrubbing remains immediate and the displayed clock lands on the player seek.
- Skip visibility changes exactly at segment boundaries.
- Completion, autosave and scrobble behavior sees the raw position cadence.
- Media switching cannot publish an old position into the new item.
- Existing lifecycle/wakelock behavior remains intact.

The current `video_player_navigation_test.dart` does not instantiate the real
player and cannot protect this work. The pure clock/coordinator tests above and
at least one widget harness with a fake player event adapter are prerequisites,
not optional follow-up coverage.

### Exit gate

- Flutter frame/rebuild tracing confirms no position-driven root rebuild.
- No functional-invariant failures.
- The baseline suite shows lower or equal energy, CPU and dropped frames on all
  tested Flutter platforms. A platform regression over run-to-run noise blocks
  release.

---

## Phase 2 — Android, without conflating phone and TV

### 2A. Android phone/tablet renderer spike

Run three modes behind a local developer flag, one mode per player session:

1. Current media-kit baseline: `vo=gpu`, `hwdec=auto-safe`.
2. libmpv direct MediaCodec interop: `vo=gpu`, `hwdec=mediacodec`.
3. Direct surface output: `vo=mediacodec_embed`, `hwdec=mediacodec`.

Mode 2 is not automatically safe: mpv documents color/10-bit limitations for
direct Android MediaCodec interop. Mode 3 may remove more of the GPU/copy path,
but media-kit's `SurfaceProducer` integration must first prove that this mode can
present frames correctly; it must not be described as equivalent to a native
Media3 `SurfaceView` without measurement. mpv also documents that OSD, subtitle
rendering and video filters are unavailable. Debrify draws subtitles in Flutter,
which may help, but that does not waive the full feature matrix.

For each mode verify:

- actual `hwdec-current` and output after first frame;
- black-frame/surface recreation on rotate, background, PiP and episode switch;
- SDR/HDR colors, 10-bit gradients, rotation metadata and aspect modes;
- embedded/addon subtitles, external audio, seeking and speed;
- IPTV recording and error recovery;
- power, CPU/GPU, thermal state and dropped frames.

After Phase 0 establishes the noise floor, adopt a renderer mode only if it
improves median energy by at least 10% in the common suite, has no case more than
5% worse, passes every applicable feature, and the measured distributions do not
overlap enough to make the verdict ambiguous. Raise these thresholds when a
device's run-to-run variation is larger; never subtract “measurement noise” by
judgment. Otherwise retain the current mode.

### 2B. Native Media3 decision gate for Android phone/tablet

If Phase 1 plus the safe libmpv renderer winner remains materially worse than a
Media3 reference, spike a native `PlayerView`/`SurfaceView` surface with Flutter
controls above it. Do **not** copy the large Android TV activity or switch the
whole phone player until the spike proves:

- Flutter overlay composition and touch/rotation work over `SurfaceView`;
- the complete backend event contract can be represented without duplicate or
  stale completion, position and error events;
- source headers, separate audio, track selection, subtitles, PiP, live streams
  and recording have explicit implementations or explicit per-content fallback;
- one backend owns audio and the visible surface for the entire media session.

Only justify a production Media3 phone backend if two representative phone/tablet
classes remain at least 15% worse than the native reference after Phase 1. Pick
the backend before creation. Automatic fallback is allowed only before first
frame; after first frame, retrying with the old backend is a full session restart.

### 2C. Android TV

Keep the existing native Media3 `SurfaceView` player. Add the same measurement
fields and decoder-name capture. Consider Media3 video tunneling only for tested
TV models and high-resolution cases that are inefficient or drop frames; it is
device-specific and must be kill-switchable. Test custom subtitles, audio offset,
speed, track switching and decoder fallback before enabling it.

---

## Phase 3 — Apple devices

### 3A. iPhone/iPad and tvOS media-kit path

First capture whether each sample uses `videotoolbox`, `videotoolbox-copy`, or
software. After Phase 1, compare the default with an explicit direct
`videotoolbox` candidate behind an Apple-only developer flag. Never report
hardware success from `hwdec=auto` alone.

Validate:

- color range, 10-bit/HDR behavior and display-mode changes;
- texture recreation on rotation, resize, background/foreground and AirPlay;
- PiP on iPhone/iPad;
- interruptions, route changes and audio-session ownership;
- subtitles, external audio, tracks, seek, speed and live playback;
- long-run thermals and dropped frames on iPad and Apple TV.

Do not treat Apple TV as an iPad: `Platform.isIOS` is also true on tvOS, so each
handheld-only change must continue to exclude `PlatformUtil.isTvOS`.

### 3B. AVPlayer decision gate

AVPlayer/AVPlayerLayer is the Apple-native candidate for supported HLS/MP4
content, but it does not automatically cover Debrify's broad MKV, codec, audio,
subtitle and recording requirements. A hybrid backend is therefore a later
optimization, not the first fix.

Only start a production AVPlayer backend if post-Phase-1 measurements show a
material, repeatable gap on both iPhone/iPad or a justified tvOS-specific gap.
Before integration, define a `PlayerBackend` contract covering transport,
source and presentation clocks, tracks, external media, first frame, seek
completion, buffering, errors and session generations. Select the backend from
known source capabilities before player creation. Never switch engines
seamlessly after first frame.

For tvOS specifically, keep the conclusions in `TVOS_4K_PLAYBACK_PLAN.md`:
retain media-kit, keep AetherEngine parked, and evaluate HDR/4K separately on a
real HDR 4K display. Battery work is not authorization for a second FFmpeg
family or a lossy TrueHD-to-EAC3 bridge.

---

## Phase 4 — desktop and web

### macOS, Windows and Linux

Ship the Phase 1 UI change first. Capture `hwdec-current`, output, codec,
resolution, CPU/GPU and energy for each machine. Only add an explicit decoder
preference when it beats `auto` on a supported matrix:

- macOS: VideoToolbox direct versus copy;
- Windows: D3D11VA direct versus copy with the active GPU context;
- Linux: VAAPI, NVDEC or another backend selected by detected capability, never
  one global Linux default.

Keep software fallback for unsupported streams so an energy optimization never
becomes a playback failure. A decoder preference needs a local kill switch and
must retain correct HDR/color and external-display behavior.

### Web

The browser owns decode, so do not expose a fake libmpv decoder status. Apply
the UI-clock isolation, avoid hidden-control updates, and measure browser CPU,
GPU/media diagnostics and dropped frames. Prefer browser-native media timing
signals where available, but keep the same generation and UI-cadence rules.

---

## Rollout and rollback

1. Land diagnostics and benchmark harness separately from behavior changes.
2. Land Phase 1 behind a short-lived comparison flag until the functional and
   rebuild tests pass, then make it the common default.
3. Keep renderer experiments as platform-scoped flags; never share one enum
   across Android MediaCodec, Apple VideoToolbox and desktop decoders.
4. Roll out one platform and device tier at a time.
5. A renderer flag may return to the known path on startup failure before first
   frame only after disposing the failed backend and starting a fresh media
   generation. Failures after first frame offer a complete retry with the known
   backend instead of running two engines at once.
6. Aggregate telemetry, if added at all, uses the existing analytics consent
   policy and contains only platform/decoder/result counters—no media identity.
7. Preserve the previous backend for at least one stable release and include a
   local/user-facing fallback if a platform renderer is still experimental.

---

## Review findings and resolutions

This plan was reviewed against the current launcher, Flutter player, Android TV
activities, vendored tvOS media-kit renderer, and the separate tvOS 4K plan.

### Major risks found during review

1. **A universal hardware-decoder fix would be wrong.** Android MediaCodec,
   Apple VideoToolbox, Windows D3D11VA and Linux VAAPI/NVDEC have different
   safety and presentation constraints. Resolved by independent platform flags
   and runtime verification.
2. **The Android phone is already hardware-decoding.** Forcing hardware decode
   would not remove its confirmed `mediacodec-copy` presentation cost. Resolved
   by separating decoder and renderer measurements and testing direct modes.
3. **`mediacodec_embed` trades features for efficiency.** Mitigated by a
   user-facing renderer choice, a one-shot startup compatibility restart, and a
   persisted Automatic fallback. It remains a product-selected default pending
   the broader device/codec feature matrix; automatic fallback cannot detect
   visually incorrect HDR or 10-bit colour.
4. **The position stream is business logic, not just UI.** Naively throttling it
   could break completion, skip, resume and scrobbling. Resolved by preserving
   raw cadence and throttling only leaf UI publication.
5. **A native backend cannot be a mid-stream fallback.** Two players can race
   audio, completion and saved state. Resolved by one backend per generated
   session and restart-only fallback after first frame.
6. **Android TV already has the desired Android surface architecture.** Resolved
   by keeping it and limiting work to measurement and optional tested tunneling.
7. **AVPlayer is not a drop-in replacement for Debrify's content surface.**
   Resolved by making it a measurement-triggered later phase with per-content
   selection and the existing backend as fallback.
8. **tvOS battery work could accidentally restart the rejected 4K integration.**
   Resolved by explicitly retaining the reviewed `TVOS_4K_PLAYBACK_PLAN.md`
   conclusion.
9. **Release diagnostics can leak media identity or misattribute async results.**
   Resolved by a fixed privacy-safe schema and media-generation invalidation.

### Second-pass findings

1. **The initial decoder probe was not a stable verdict.** The existing trigger
   can run while `current-vo` is still null, and a single sample misses a later
   hardware-to-software fallback. Resolved by waiting for stable post-frame
   values, observing changes, and keying generations to app-owned opens.
2. **Hidden controls and the skip overlay had conflicting requirements.** The
   skip action intentionally appears while controls are hidden. Resolved by
   stopping only clock-control notifications while keeping an isolated,
   boundary-only skip notifier.
3. **The reference-player wording could force an invalid comparison.** Apple's
   native player, for example, cannot open every remux Debrify supports.
   Resolved by same-file numeric comparisons only for mutually supported media
   and directional third-party comparisons for broader formats.
4. **The proposed UI tests lacked a practical seam.** Existing navigation tests
   duplicate tiny helper logic and never instantiate the player. Resolved by
   requiring a pure clock/coordinator plus a fake-event widget harness.
5. **`mediacodec_embed` was described too optimistically.** Direct mpv output
   through media-kit's Flutter surface is not automatically the same thing as
   Media3 on a native `SurfaceView`. Resolved by adding a presentation-feasibility
   gate before energy or feature claims.
6. **Fixed percentages could hide noisy data.** Resolved by calibrating against
   Phase 0 variance and rejecting ambiguous distributions.

### Review verdict

**No unmitigated major design issue remains in the twice-reviewed plan.** The unknowns are now
explicit measurement gates rather than assumptions: Apple decoder mode, power
delta after the shared UI fix, Android direct-mode feature parity, and whether
any native phone/Apple backend is justified. Those unknowns can stop a later
phase without blocking the safe Phase 0 and Phase 1 work.

This verdict applies to the plan, not to unimplemented optimizations. Battery
improvement is considered proven only after the release-build measurement gates
pass on physical devices.

---

## Primary references

- Android Media3 battery guidance: SurfaceView is preferred, and TextureView
  can raise total playback power substantially on some devices:
  https://developer.android.com/media/media3/exoplayer/battery-consumption
- Flutter performance guidance: a high-level `setState` rebuilds all
  descendants, so state changes should be localized:
  https://docs.flutter.dev/perf/best-practices
- mpv hardware decoding and Android output documentation, including
  `hwdec-current`, copy-mode cost, direct MediaCodec cautions and
  `mediacodec_embed` feature limits:
  https://mpv.io/manual/master/
- media-kit architecture and Android `SurfaceProducer` output:
  https://github.com/media-kit/media-kit
- Apple energy guidance on avoiding unnecessary UI/graphics updates:
  https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/AvoidExtraneousGraphicsAndAnimations.html
- Apple AVPlayer/AVPlayerLayer presentation guidance:
  https://developer.apple.com/documentation/avfoundation/avplayer/
