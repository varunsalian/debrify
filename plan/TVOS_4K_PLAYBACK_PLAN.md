# Apple TV — true 4K playback via the hardware video plane

Status: **Phase 0 done and both gates passed on device (2026-08-07). Nothing
else built. Awaiting a go/no-go.**

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
