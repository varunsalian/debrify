# Phase 2 — the tvOS native video layer: true 10-bit, HDR, Dolby Vision

Rev 2 — 2026-08-11. Rev 1 reviewed by Codex; four architectural
corrections folded in below (marked "rev 2"): the wid path is
binary-verified but NOT an upstream contract; the hole-punch requires
Runner-level Flutter transparency, not just a plugin mode; HDR needs
AVDisplayManager display-mode switching and the DV claim is corrected to
"correct rendering", not native DV signaling; fallback is a cold-restart
state machine with explicit VO-shutdown acknowledgement.

Planning-only deliverable, deliberately: every step of
a renderer migration needs eyes on the physical TV (HDR handoff, EDR
flicker, hole-punch compositing artifacts are all invisible in logs), so
implementation waits for an attended session. This document is written to
be executable the day that session starts.

## Why

The Dart player's tvOS video path is mpv's OpenGL render API → GLES3 →
BGRA8 CVPixelBuffer → Flutter texture. That pipeline is 8-bit SDR by
construction — the 10-bit blue-screen fix (PLAYER_TVOS_10BIT_PLAN.md)
made it *correct*, not *faithful*. Full fidelity needs mpv rendering to a
surface the display pipeline scans out directly.

## Verified foundations (from the shipped karelrooted static libmpv)

`strings` on `Libmpv.xcframework/tvos-arm64/libmpv.a` confirms:

- `_ra_ctx_vulkan_moltenvk` + `context_moltenvk.m` — the MoltenVK GPU
  context is COMPILED IN. mpv's moltenvk context takes a **CAMetalLayer**
  handle via the `--wid` option.
- `_vt_pl_init` + `hwdec_vt_pl.m` — the libplacebo VideoToolbox interop:
  zero-copy P010/NV12/DV mapping into Vulkan-on-Metal.
- Feature list includes `libplacebo`, `vulkan`, `vulkan-interop`,
  `videotoolbox-pl`, `moltenvk`.
- shaderc + lcms2 present (shader compilation, color management).

So `--vo=gpu-next --gpu-api=vulkan --gpu-context=moltenvk
--wid=<CAMetalLayer*>` is a configuration the shipped binary contains —
review went deeper and confirmed its `context_moltenvk.m` object reads
mpv's WinID, hands it to `vkCreateMetalSurfaceEXT` as a CAMetalLayer, and
tracks `drawableSize` on reconfigure.

**Rev 2 caveat:** this is an MPVKit-lineage patch, not an upstream mpv
contract — upstream documents window embedding for X11/Win32/macOS only.
"The shipped binary contains the required candidate path" is the honest
claim. Hence the attended session's FIRST task is a minimal hardware
spike (SDR file → `current-vo=gpu-next`, `hwdec-current=videotoolbox`,
first frame presented, clean teardown) before any app integration, and
rebuilding/patching libmpv+MoltenVK stays on the books as the
contingency if the spike fails.

## Architecture — the hole-punch, which this codebase already ships

Same pattern as the Android TV native player and the Home hero trailer
(SurfaceView + `BlendMode.clear` hole, see project_home_hero_trailer):

1. **Runner-level view hierarchy (rev 2 — this is NOT plugin-only
   work):** Android's hole-punch works because its Flutter surface is
   transparent; the tvOS Runner currently installs an OPAQUE
   FlutterViewController as the window root, and clearing pixels inside
   an opaque surface exposes nothing. The Runner therefore changes to: a
   native container view filling the window; a `UIView` subclass backed
   by `CAMetalLayer` (layer delegate = its containing view, per
   MoltenVK's guidance) as the BOTTOM sibling; the FlutterViewController
   with `viewOpaque = false` and a clear background ABOVE it. Real
   siblings — never a sublayer of Flutter's backing layer.
2. **mpv wiring:** layer mode is decided BEFORE player construction:
   `vo=gpu-next`, `gpu-api=vulkan`, `gpu-context=moltenvk`,
   `wid=<layer pointer>`, `hwdec=videotoolbox` (vt_pl engages
   automatically). No `VideoController`/texture exists in this mode — the
   render API and `vo=gpu-next` are mutually exclusive by design.
3. **Flutter side:** the player screen paints a transparent hole
   (`BlendMode.clear`) where video shows; controls and overlays composite
   above it exactly as the Android TV player's UI does; subtitles render
   inside mpv (libass). **Full-screen only in v1** — the native view
   fills the window, so no Dart bounds channel and no overscan/scale
   coordinate conversion exists to get wrong.
4. **HDR output (rev 2/2.1 — THREE halves, all required):**
   *(0) surface depth*: the layer's pixel format must be explicitly
   10-bit-capable (`bgr10_xr` / `rgba16Float`-class — whatever MoltenVK
   exposes as the swapchain format for the layer) and the Vulkan
   swapchain format verified via libplacebo's swapchain report at spike
   time — PQ + EDR flags on an 8-bit surface would silently rebuild
   today's quantization one layer down;
   *(a) rendering*: `wantsExtendedDynamicRange` + PQ colorspace on the
   layer + libplacebo `target-colorspace-hint` for HDR pixel output;
   *(b) display mode*: tvOS switches the TV's mode via
   `AVDisplayManager`/`AVDisplayCriteria` — an AVFoundation-side
   integration in the Runner, without which EDR behavior on tvOS is
   undocumented and cannot be assumed. Dolby Vision P5's acceptance
   target is **correct color via libplacebo reshaping into HDR output**
   — NOT native DV signaling; the TV badges HDR10, never Dolby Vision,
   and the plan promises nothing else.

## Scope fence

- **tvOS full-screen player only.** Ambient trailers, PiP surfaces, the
  Spotlight hero — all stay on the texture path (they composite INSIDE
  Flutter UI and must remain textures). No partial-screen geometry in v1.
- Behind a setting (`tvos_video_layer` — default OFF at first, flipped
  default only after soak), with the 10-bit remedy + software toggle
  remaining as the texture path's protections.
- **Fallback is a cold restart, never an in-place VO switch (rev 2):**
  "attach succeeded" proves nothing — the Vulkan device/swapchain is
  created when playback creates the VO, so layer mode is confirmed only
  by `current-vo=gpu-next` + a first-frame observation, and failure means:
  stop and dispose the layer-mode player, KEEP the CAMetalLayer alive
  until VO shutdown is POSITIVELY acknowledged — rev 2.1: that means a
  real native completion signal (the plugin observes
  `MPV_EVENT_SHUTDOWN` / destroys the handle itself and then reports
  back over the channel), with a bounded timeout whose expiry FAILS
  CLOSED by leaking the layer for the process lifetime rather than
  freeing memory a swapchain may still touch. `Player.dispose()`'s
  five-second delayed `mpv_terminate_destroy` is explicitly NOT an
  acknowledgment, and the texture path's SwappableObjectManager is not
  an applicable lifetime mechanism. Only then build the fresh
  texture-path player + VideoController. All before video is first
  revealed.
- **Lease fails closed in layer mode (rev 2):** the texture path may
  proceed after the 3-second VideoOutputLease timeout; layer mode never
  attaches without actually owning the lease.
- tvOS PiP: explicitly unsupported in layer mode v1 (the app's PiP
  service is Android-only today anyway).
- Android/iOS/desktop untouched. Runner changes are tvOS-only.

## Known hazards to budget for (why this is attended work)

1. **The two-output SIGABRT class**: this plugin has crashed before when
   two video outputs coexisted; layer mode must hold the same
   `VideoOutputLease` the texture path does, and the mode decision must be
   made BEFORE player construction (no runtime switching in v1).
2. **`wid` lifetime**: mpv must be fully torn down before the CAMetalLayer
   is removed — the reverse order is a use-after-free in the vulkan
   swapchain. Mirror the disposal ordering the texture path's
   SwappableObjectManager already enforces.
3. **Screenshots/recording/`stream-record`**: verify each against
   gpu-next; `screenshot-raw` behavior differs from the GL path.
4. **Subtitle rendering scale**: mpv renders subs at video resolution on
   the layer (better than today's texture, but verify SDH sizing).
5. **The overscan safe-area**: the layer is positioned in SCREEN
   coordinates while Flutter works in the inset logical space — reuse the
   inset math from ScaledFlutterJNI's tvOS analogue carefully.
6. **EDR + screensaver/idle dimming interactions** need physical-TV eyes.

## Implementation order (rev 2 — spike-gated)

1. **Hardware spike in a minimal native host** (no Flutter): CAMetalLayer
   + wid + gpu-next + vt_pl on the real Apple TV — SDR file plays, HW
   decode confirmed, **swapchain format verified 10-bit-capable**, clean
   teardown with a positive shutdown signal. This gates everything;
   failure means the libmpv rebuild contingency, not app work.
2. **Flutter transparency spike**: `viewOpaque=false` Runner + sibling
   layer + BlendMode.clear hole — UI composites correctly over live
   video.
3. `AVDisplayCriteria` display-mode switching + EDR negotiation.
4. Plugin abstraction (layer mode), the cold-restart fallback state
   machine, and the setting.
5. SDR parity soak → HDR10 verification → DV P5 color verification.
6. Recording/screenshot audit; then the default-flip decision.

Estimated 2–3 weeks attended, matching the original assessment.
