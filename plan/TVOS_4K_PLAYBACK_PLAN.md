# Apple TV — true 4K playback via the hardware video plane

Status: **NO-GO on this plan as written.** Phase 0's two gates passed on device
(2026-08-07), but a review found the plan under-scopes the player integration
and over-reads the 4K evidence. Superseded by the narrower Spike 2 below.
Nothing beyond the probe is built.

---

## Why this exists

tvOS hands UIKit apps a **1080p** drawing surface and upscales to the panel.
Measured on the Apple TV 4K (3rd gen), not assumed:

```
screen.bounds=(1920x1080)  scale=1.0  nativeBounds=(1920x1080)  nativeScale=1.0
```

There is no API to raise it, so Flutter is already using everything it is
given. But video does not have to go through that surface: `AVPlayerLayer` /
`AVSampleBufferDisplayLayer` sit on the **hardware video plane**, composited by
the display pipeline at OUTPUT resolution. That is how Apple's own player shows
4K HDR while the UI stays 1080p, and it is the same trick as the Android
SurfaceView underlay this app already ships for trailers.

Debrify's tvOS player currently goes mpv → Flutter texture, so it composites
through the 1080p surface. Measured cost, same box, same network, same evening:

| Path | Resolution |
|---|---|
| Flutter texture (`video_player`, AVPlayer-backed) | 1280x720 |
| Native `AVPlayerViewController`, Apple 4K DV HLS sample | 2560x1440 |
| **AetherEngine, a 69 GB 4K HDR10 MKV remux (TrueHD)** | **3840x2160** |

---

## What Phase 0 proved

### Gate 1 — Flutter can render transparently on the tvOS fork ✅

`FlutterViewController.isViewOpaque = false` (renamed from `viewOpaque` on this
fork) plus a clear `backgroundColor`, with a native view inserted at index 0 of
the root view. A magenta test layer showed through with the Flutter UI
composited over it. **A video plane can live behind the Flutter UI.** This was
the gate that could have ended the idea outright.

### Gate 2 — the engine plays what AVFoundation refuses ✅

[AetherEngine](https://github.com/superuser404notfound/AetherEngine) against the
worst-case file (HEVC 3840x2160 10-bit PQ/BT.2020, TrueHD 8ch + EAC3, PGS + SRT,
69 GB):

- `presentationSize=(3840.0, 2160.0)`, `state=playing`, `nativeAV=true`
- full 2h45m duration parsed, 2 audio tracks, **32 subtitle tracks**
- TrueHD handled: `audio: codec=truehd (bridge required), decoding + EAC3
  re-encode`, 8ch → 6ch @ 768 kbps
- Dolby Vision P7 detected and mapped: `source-format=dolbyVision
  effective-format=hdr10`, `DisplayCriteria SET: format=hdr10 codec=dvh1`
- Mechanism: demuxes MKV, **remuxes to fMP4 segments served from a local HTTP
  server**, which AVPlayer plays — hence the plane. Windowed 32 MB range
  requests, so a 69 GB remote file starts in seconds.

---

## Still unknown (do not plan as if these are settled)

1. **HDR passthrough end-to-end.** The engine asked tvOS to switch and logged
   `panelIsHDR=false` — the display here is a non-HDR monitor. Needs an HDR TV.
2. **The 8 `mk.NativePlayer` call sites.** mpv-specific property setting
   (hardware decode, cache, user-agent and similar). No automatic equivalent;
   each needs a mapping or a deliberate drop on tvOS.
3. **Subtitle fidelity vs mpv.** Cues arrive as styled runs with placement
   (ASS-relative), which is better than expected, but we paint them.
4. **Seek behaviour** on a large remote file through the segment producer.
5. **CPU/thermal cost** of demux + remux + audio re-encode during long playback.
6. **IPTV live streams** — untested against this engine.

---

## Plan

Each step is independently testable and lands as uncommitted changes for a
device test before the next one starts.

### Step 1 — `PlayerBackend` abstraction (Dart only, no device)
Extract the surface the player actually consumes today — measured as **~25
members across 5 files, 109 references**: `open/play/pause/seek/stop/dispose`,
`setRate/setVolume/setAudioTrack/setSubtitleTrack`, streams for
`position/duration/buffering/playing/completed/error/width`, and
`state.tracks/duration/position/volume/width/height`. Implement it once over
media_kit, change nothing else.
**Exit:** every platform behaves exactly as before; analyzer clean; tests pass.
**Risk:** low. This is the step that makes the rest reversible.

### Step 2 — native surface behind Flutter
Add AetherEngine via SPM to `tvos/Runner.xcodeproj` (merge into the EXISTING
`packageReferences` / `packageProductDependencies` arrays — a second copy is
silently ignored). Insert the player view at index 0, set `isViewOpaque = false`.
Carry over the Android underlay invariant: **nothing may paint an opaque layer
over the video region.**
**Exit:** a hard-coded URL plays full-screen behind the Flutter UI on device.

### Step 3 — bridge
MethodChannel for transport and track selection; EventChannels for state,
clock, and subtitle cues. Keep it a thin translation of the engine's API.
**Exit:** Dart can drive playback and observe position/state/tracks.

### Step 4 — wire the backend, behind a flag
Second `PlayerBackend` implementation over the bridge, selected on tvOS by a
pref (`tvos_video_engine`: `mpv` default, `aether` opt-in). mpv stays the
fallback for anything the engine refuses.
**Exit:** the existing player UI drives the native engine end to end — play,
pause, seek, rate, audio and subtitle track switching, resume, next episode.

### Step 5 — subtitle overlay
Paint `$subtitleCues` in Flutter: text and styled runs with placement, plus PGS
bitmaps. **Scope: correct positioning and basic styling. NOT full ASS.**
**Exit:** embedded SRT, ASS and PGS all render legibly at the right position.

### Step 6 — device pass and edges
Real content end to end, HDR on a real HDR TV if one can be borrowed, seek
behaviour, long-playback thermals, background/foreground, Siri Remote.
**Exit:** the flag can default to `aether` on tvOS, or a written reason why not.

**Estimate: ~5-6 days**, Step 5 the most likely to stretch.

---

## Non-goals

- Android, iOS and desktop are untouched. mpv remains their engine.
- IPTV and ambient trailers stay on mpv until the main player is proven.
- No full ASS styling in v1.
- No native tvOS player UI. The Android native player is 20,519 lines of Kotlin
  because it owns its UX; that story is not being started here.

---

## Licensing

Debrify is **Polyform Noncommercial**. AetherEngine is **LGPL-3.0 with an Apple
Store / DRM exception**, and ships FFmpeg/LibDovi as dynamic frameworks — link
dynamically and this is compatible. **KSPlayer was rejected**: GPL by default,
which is not compatible; its LGPL version is paid.

Dependency risk is real and worth restating: ~140 stars, anonymous author,
though 2,078 commits and releasing actively (6.12.1 shipped the same day it was
evaluated). Pin the version, read the source before depending on it, and keep
mpv as the fallback so a stall upstream is survivable.

---

## Reference

- **Probe harness:** `scratchpad/avprobe`, bundle `com.varunsalian.avprobe`,
  installed on the TV. Links AetherEngine via SPM, plays a URL behind Flutter,
  logs `state/phase/format/presentationSize/tracks` every 5s. Keep it — it
  re-measures any of the above in minutes.
- **Deploy:** `scratchpad/deploy_tv.sh` (build → install → launch, ~2 min).
- **Device console:** `xcrun devicectl device process launch --device Bedroom
  --console --terminate-existing <bundle>`. Dart `print` does NOT appear in a
  release build; the tvOS `debugPrint` → NSLog bridge in `main.dart` is what
  makes Dart logs visible.
- **Screenshots:** System Events → Xcode → Devices → button "Take Screenshot";
  the PNG lands on the Desktop. Kill any `--console` session first, since it
  terminates the app when it exits.

---

# Review findings (Codex, 2026-08-07) — plan revised to NO-GO

## Corrections to the evidence above

- **The 2160p number does not prove 4K reached the panel.**
  `presentationSize` is the decoded item's dimensions; for a non-adaptive MKV it
  simply reports the file. The 720p-vs-1440p comparison IS meaningful (adaptive
  HLS picks a variant by render target), but "true 4K output" remains unproven.
  Proving it needs the HDMI output format, not a decoder property.
- **The `mk.NativePlayer` sites were mischaracterised.** They are Android audio
  effects, subtitle delay, file-format probing and `stream-record` —
  `video_player_screen.dart:1754`, `:3166`, `:4682` — not decode/cache tuning.
- **The ~25-member surface is understated.** Missing: currently-selected track,
  log stream, first-frame/readiness, render mode, external audio, external
  subtitle registration, seek completion, capabilities, native escape hatch.
- **One clock is not enough.** Aether separates playback time from displayed
  source PTS; subtitles must render against `sourceTime` while resume/UI use
  presentation time. Collapsing them drifts subtitles across seeks and remux
  epochs.

## Scope the six steps missed

Backend event semantics silently underpin: skip segments
(`video_player_screen.dart:1186`, `:2107`), resume autosave every 6s (`:2231`,
`:7679`), Trakt/Simkl progress and per-seek hooks (`:8067`), completion →
next episode (`:2198`), wakelock/lifecycle (`:2123`). Duplicated, reordered or
stale events can scrobble the wrong episode, auto-advance twice, or save the old
position against the new item.

Also absent: external subtitles (the current path preserves raw bytes so libmpv
can detect legacy encodings, `:10597`, `:10863`), `AVAudioSession` ownership,
interruptions and route changes, HDMI/audio-format changes, `MPNowPlayingSession`
and remote commands, PiP (tvOS has no sample-buffer PiP, and a Flutter-painted
subtitle overlay cannot appear in a native PiP window anyway).

**IPTV contradiction:** Step 4 selects the engine from a global tvOS pref while
the non-goals keep IPTV on mpv — but one `VideoPlayerScreen` serves both, so
per-content routing is required *before* player creation. IPTV's error detection
(`:5170`) also assumes events only count after `open()` returns; a native bridge
can emit first-frame before the channel result and produce false timeouts.

**Error/retry is a state machine, not an edge case:** PikPak recovery reopens the
same player and cross-checks stream state (`:6473`, `:6610`). Whether an engine
failure continues that loop, falls back immediately, or falls back only after
retries is undefined.

## Fallback redesign (the flag itself is fine)

Automatic "fall back for anything the engine refuses" is not sound: it creates
two owners of audio and the visible surface. Defensible v1:

- **one backend per media session**, chosen before creation;
- **every event tagged with a session generation**, stale ones dropped;
- **one-way fallback only before first frame**; after first frame, offer
  "Retry with mpv" as a full session restart, never a seamless swap.

Note `MediaKitInit.ensureInitialized()` is unconditional (`:1051`), so today even
an engine session would initialise mpv. Backends are not actually isolated.

## Other reasons to hold

- **TrueHD is re-encoded to lossy EAC3 5.1** (8ch → 6ch @ 768 kbps). That is an
  audio REGRESSION for exactly the audience that cares about 4K remuxes, and it
  partly cancels the reason for doing this.
- Debrify would ship and test **two playback stacks, two FFmpeg families, two
  rendering models** — permanently.
- The tvOS port has **almost no player-level automated coverage**
  (`test/video_player_navigation_test.dart` doesn't even instantiate
  `VideoPlayerScreen`), so "tests pass" protects nothing in Step 1.
- The licence claim was too categorical: the Apple Store exception preserves
  source/licence obligations for Aether and modifications; FFmpeg configuration
  and notices still need a release compliance review.

## Revised direction — Spike 2 before any integration

1. **Prove actual HDMI output.** Read the real output format during playback
   (tvOS video/display mode, or an HDR TV's own badge), not a decoder property.
   If the plane doesn't actually deliver 2160p to the panel, stop here.
2. **Define and test the full contract** — backend, render, and event semantics
   including session generations, source-vs-presentation time, first-frame,
   completion, seek-landed, and error/retry — against the real feature list
   above, BEFORE touching the 11k-line player screen.
3. Only then re-cost the integration. It is larger than 5-6 days as scoped.

---

## Spike 2, step 1 result (2026-08-07): output stayed 1080p

Measured during playback of the 4K remux through AetherEngine on the video plane:

```
[output]  currentMode=1920x1080  bounds=1920x1080  nativeBounds=1920x1080  scale=1.0
[aether]  presentationSize=(3840.0, 2160.0)  nativeAV=true
```

`UIScreen.currentMode` never left 1080p while the decoder reported 2160p —
confirming the review's point that `presentationSize` describes the FILE, not the
output. Two readings remain, and this hardware cannot separate them:

1. The attached display (a non-HDR monitor) is the limit and the box is simply
   outputting 1080p — the 4K case is then untestable here, though it may still
   hold on a 4K panel.
2. `UIScreen.currentMode` mirrors the UI surface on tvOS and never reports the
   HDMI mode — in which case this probe is inconclusive as well.

**Discriminator:** the TV's own Settings > Video and Audio > Format, and
ultimately re-running this on a genuine 4K/HDR television.

**Consequence:** the benefit that justifies the whole integration is UNPROVEN on
the available hardware. Do not start the integration until it is demonstrated on
a 4K panel. `AVDisplayManager` is not exposed as `UIScreen.displayManager` on
this SDK, so a future attempt needs another route to the real output format.
