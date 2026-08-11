# Apple TV blue-screen on 1080p/4K videos — root cause & fix plan

Rev 3 — 2026-08-11. Rev 1 (blanket pin) and rev 2 (reactive ladder)
reviewed by Codex; rev 3 resolves rev 2's two High findings (property
persistence across media, transitional-event double-fire) and folds in the
four Mediums/Lows. Scope: tvOS only. Android, iOS, desktop and the trailer
engines are byte-identical.

## Symptom

Some 1080p and 4K videos show a solid blue screen on Apple TV (media_kit /
libmpv Dart player); audio and the progress bar behave normally.

## Root cause — strong hypothesis; this change proves or refutes it in the field

Established directly from the repository:

- tvOS runs `hwdec=auto` (media_kit_video_tvos
  `native_video_controller/real.dart:121`) → VideoToolbox.
- The native output is mpv's OpenGL render API into an OpenGL ES 3 context
  (`TextureHW.swift:59`, `OpenGLESHelpers.swift:6`).
- The shipped static libmpv was built `-Dios-gl=enabled
  -Dvideotoolbox-gl=disabled` (verified via `strings` on the tvOS
  `libmpv.a`), so the zero-copy interop is `ios-gl`.
- mpv's `hwdec_ios_gl.m` maps CVPixelBuffer planes with 8-bit
  GL_LUMINANCE[_ALPHA] textures (the `find_la_variant` workaround); Apple
  GPUs expose no 16-bit norm texture formats on GLES.

Hypothesis: high-bit-depth sources (HEVC Main 10 ⇒ **P010** buffers — and
equally any 10/12/16-bit biplanar VT output such as p210/p410 from
high-bit 4:2:2/4:4:4 content) hit that 8-bit mapping and render as a blue
field — the signature reported for mpv's VT+GL iOS path in mpv#7846
(P010 → blue screen). 8-bit sources produce NV12 and map fine, which is why
only *some* 1080p/4K files fail. The same mpv#7846 thread records imperfect
HDR color under forced nv12 on a 2020-era build — so the design never
trusts one rung, reports what it saw, and keeps a software rung and a
manual override behind it.

The 10-bit-capable `vt_pl` interop is in the binary but needs the Vulkan
render API; the Swift texture layer hardcodes `MPV_RENDER_API_TYPE_OPENGL`.
Migrating that is the durable fix for true 10-bit / Dolby Vision P5 —
recorded as follow-up, out of overnight scope.

## Design — reactive remedy ladder (tvOS only)

Nothing changes at open (except the session hint below, which only exists
after a bad file already played). The remedy engages only when the decoder
itself reports a format the GLES interop cannot represent.

### Detection

`_handleDecoderProbeParams` (fed by the existing `videoParams` listener,
video_player_screen.dart:2430 — all platforms, outside the
native-construction window flagged in `_installDecoderObservers`) hands
`VideoParams` to the remedy. Trigger: `VideoParams.hwPixelformat` ∈
{p010, p012, p016, p210, p212, p216, p410, p412, p416} — the complete
high-bit biplanar family (FFmpeg pixfmt.h). `null` (software decode),
`nv12`, `uyvy422` never trigger. High-bit 4:2:2/4:4:4 content triggering is
*intentional*: it takes the same broken 8-bit GLES mapping today, so an
8-bit conversion that renders beats fidelity that doesn't.

### The ladder — serialized, poll-verified, never event-escalated

New `TvosDecodeRemedy` (lib/services/tvos_decode_remedy.dart). mpv property
get/set injected as functions. Explicit phase machine:
`idle → applyingRung1 → applyingRung2 → settled(rung) | gaveUp`.

- A `videoParams` event can do exactly ONE thing: start the ladder from
  `idle` when detection fires. Events arriving in any other phase are
  ignored — the `no→auto` cycle emits transitional params (reset, software,
  stale-P010, final) and none of them may drive decisions (rev 2 High #2).
- **Rung 1 — hardware, 8-bit surfaces.**
  `set hwdec-image-format=nv12` → **read the property back** (media_kit's
  `setProperty` discards mpv's error code; the read-back is the only
  truth; mismatch ⇒ skip the cycle, escalate) → cycle `hwdec` `no` →
  `auto` to re-initialise the decoder in place (no app-level player
  rebuild and no explicit seek; mpv performs internal seeks — brief
  rebuffer on network streams is accepted, see Risks).
  Then **verify by polling**, not by stream events: up to 12×250ms direct
  reads of `video-params/hw-pixelformat` until two consecutive reads agree
  (the codebase's existing two-read stability protocol). Stable good value
  ⇒ `settled(nv12)`. Stable bad value ⇒ rung 2. Generation checked after
  every await; a generation change aborts to `idle`.
- **Rung 2 — software decode.** `set hwdec=no`; poll the same way for
  `hwPixelformat == null` ⇒ `settled(software)`; otherwise `gaveUp`
  (diagnosed, nothing else to try). Correct-but-heavy beats blue; 4K60 may
  drop frames.
- One attempt per rung per media generation, enforced by the phase machine.

### Media boundaries — explicit reset + session hint (rev 2 High #1)

Remedy properties are ordinary runtime options on a reused native player;
nothing resets them between files. So:

- `_beginMediaGeneration` (the existing session boundary) calls
  `remedy.onNewMedia()`: if anything was applied, restore
  `hwdec-image-format=no` and `hwdec=auto` before the next open, and reset
  the phase machine. A later 8-bit file therefore plays exactly as today.
- **Session hint:** if the previous file in this player session settled at
  rung 1, the reset SKIPS restoring `hwdec-image-format` (keeps `nv12`)
  and pre-applies it before the next open instead. Decoder not yet created
  ⇒ no cycle, no seek, no blue flash on the next episode of the same
  10-bit show. For 8-bit 4:2:0 files nv12 is a no-op; the hint only exists
  after a high-bit file already played in this screen session, and dies
  with the screen. The software rung is never sticky — every new file
  retries hardware.

### Diagnostics — extend the existing probe, prove the journey (rev 2 #5)

`_reportActiveVideoDecoder` gains fields, and the dedupe signature gains
the remedy state so a post-remedy report is never suppressed:
`pixelformat=`, `hw_pixelformat=` (current), `detected_hw_pixelformat=`
(what triggered, preserved by the remedy), `gamma=`, `primaries=`,
`remedy=` (none | nv12 | software | gave_up), `remedy_outcome=`
(confirmed | pending | failed — confirmed means the poll saw a stable good
format, not merely that the option write stuck). Emitted through the
existing `_emitDecoderDiagnosticOnce` native channel — no `debugPrint`, no
new machinery. The morning line for a previously-failing file should read
`decoder=videotoolbox detected_hw_pixelformat=p010 remedy=nv12
remedy_outcome=confirmed`.

### Manual escape hatch (rev 2 #6)

tvOS-only Player Settings toggle — "Force software video decoding
(compatibility)" — false-default bool beside the other player defaults in
`StorageService`, preloaded in the awaited init path (`_loadPlayerDefaults`;
`_createPlayerInstance` is synchronous and cannot read prefs itself),
consumed at controller creation as `hwdec: 'no'`, gated on
`PlatformUtil.isTvOS` (never `Platform.isIOS`). Settings row in the player
defaults card with proper focus-node lifecycle, a tvOS-gated
settings-search entry, and an "applies from the next playback" caption.
Exists for what the detector cannot see (e.g. wrong colors on a
clean-reading format). Off ⇒ zero behavior change.

## Risks, stated plainly

- `hwdec` cycling reinitializes the decoder with internal seeks: a network
  stream may rebuffer for a moment mid-remedy; live IPTV may snap to the
  live edge. Accepted — both beat an unwatchable blue stream, and the
  remedy only ever fires on files that are broken today.
- HDR-under-nv12 color fidelity is unproven on this mpv build; the
  diagnostic fields plus the owner's eyeball test decide whether HDR
  content should prefer the software rung as a follow-up.
- Dolby Vision P5 stays wrong-colored on every rung (as today); needs the
  Vulkan/`vt_pl` migration.

## Rev 3.1 — round-3 review amendments (implementation contract)

- **Poll semantics:** during verification, only the TARGET (non-triggering)
  value may terminate the poll early on two consecutive reads. A bad value
  is only final at the polling deadline — a `no→auto` cycle can serve
  stale P010 reads before the decoder transitions, and two matching stale
  reads must not escalate (or declare `gaveUp`) prematurely.
- **Property access normalization:** media_kit's `getProperty` returns `''`
  for absent properties — normalize to `null` before comparing, or the
  software rung's "hwPixelformat is null" target can never match.
- **Boundary ordering:** the media generation increments synchronously;
  `onNewMedia()` is awaited BEFORE `_player.open()`, and `_openMedia`
  re-checks its captured generation after that await (rapid zaps must not
  open an older item). Every property access (get/set) runs through a
  serial queue owned by the remedy with a generation guard inside each
  queued op — stale ladder work can neither write properties nor mutate
  the phase after a new generation starts, and `onNewMedia`'s restore
  writes are ordered after any in-flight stale access. Poll SLEEPS stay
  outside the queue so a boundary never waits behind a 3-second poll.
- **Diagnostics scheduling:** a remedy state change actively calls back
  into the screen (`_scheduleDecoderProbe`) — signature-dedupe alone would
  never re-run the probe after a settle.

## Rev 3.2 — owner decision: standard pin up front, ladder as backstop

After reviewing the trade-offs the owner chose the STANDARD approach: the
NV12 pin now applies from the first file (`pinNv12FromStart: true` — the
session-hint machinery pre-applies it at every media boundary, before the
decoder exists), which is exactly the default mpv shipped on Apple
platforms before 0.33. No first-file blue flash, no mid-play decoder cycle
in the common case. The reactive ladder is retained UNDERNEATH, unchanged:
if VideoToolbox rejects NV12 for some exotic stream and still emits a
high-bit surface, detection fires and the ladder walks to software decode.
8-bit content is NV12 already, so the pin is a no-op for it. Risk analysis
for the always-on pin: the only true-regression category would be files
that render correctly at 10-bit today — which is empty on this GL path
(that is the bug).

## Tests

`TvosDecodeRemedy` unit tests with fake property functions and a scripted
poll sequence:

- rung-1 order: format set → read-back → `no` → `auto`;
- read-back mismatch skips the cycle and escalates;
- transitional params events during any non-idle phase are ignored (incl.
  a stale P010 event mid-cycle);
- poll confirms nv12 ⇒ settled, no rung 2; poll stays P010 ⇒ rung 2;
- rung 2 poll null ⇒ settled(software); still bad ⇒ gaveUp;
- generation change mid-rung aborts and a fresh evaluate works;
- onNewMedia restores properties (and phase) — remediated → 8-bit case;
- session hint: rung-1 settle ⇒ next media keeps nv12 with NO cycle;
  software settle ⇒ next media retries hardware;
- detection set membership incl. p012; nv12/uyvy422/null never trigger.

Analyzer + existing suites stay green. Device (morning, owner):
previously-failing 1080p/4K Main10 (SDR + HDR10), known-good 8-bit file,
YouTube trailer, seek + episode transition on a remediated file (hint path:
no second blue flash), live IPTV zap on a 10-bit channel if available,
external-audio item, the settings toggle, and the diagnostic line.
