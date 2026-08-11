# Audio fidelity in the Dart player — no downgrade when the hardware can take it

Rev 2 — 2026-08-11. Rev 1 reviewed by Codex (2 High, 2 Medium); amendments:

- **Probe reads the DEVICE side.** `audio-params/*` is decoder output and
  can show six channels while the AO writes stereo — worthless as proof.
  The probe reads `audio-out-params/{channel-count,format}` (plus
  `current-ao`, and the decoded channel count as a separate
  `decoded_channels=` field), and the existing two-read stability loop
  extends to `current-ao`/`audio-out-params` so audio isn't sampled before
  the output configures.
- **Apple multichannel is OPT-IN, not default-on.** mpv's own manual warns
  `audio-channels=auto` can select layouts a route mishandles, and
  Apple's spatial/AirPlay routes are unproven territory
  (`setSupportsMultichannelContent` is absent from the mpv binary). New
  toggle "Multichannel audio (LPCM over HDMI)" — tvOS + iOS, default OFF,
  caption honest about routes. Default-on reconsidered only after the
  owner's AVR verification via the new probe fields.
- **One awaited owner for every audio property.** New
  `_configurePlayerAudio` reads BOTH settings (passthrough + system audio
  effects) plus platform, computes `ao` once
  (`audiotrack,opensles` when either Android setting needs it), then
  `audio-spdif`, then `audio-channels` — awaited before the first
  `open()`, applied at every player-instance creation site including the
  Android renderer-fallback recreate. `_attachAudioEffectSession` keeps
  only the session-id/broadcast half; it no longer writes `ao`.
- **Honest passthrough naming.** DTS-HD MA bitstreams as its DTS *core*
  over this path; the setting and captions say "AC3 · EAC3 · DTS (core)".
  TrueHD stays decode-to-PCM everywhere (no ENCODING_DOLBY_TRUEHD route in
  mpv's audiotrack).

Phase 1 of the original-quality programme (Phase 2, the Phase 1 of the original-quality programme (Phase 2, the
tvOS Metal renderer, is planned separately in PLAYER_METAL_RENDERER_PLAN.md
and deliberately not implemented unattended).

## What the shipped binaries actually support (verified by `strings`)

- **tvOS static libmpv** (karelrooted): audio output = `ao_audiounit` ONLY.
  No `ao_avfoundation` — so the Apple-sanctioned EAC3/Atmos route
  (AVSampleBufferAudioRenderer) is NOT reachable without rebuilding the
  library. `ad_spdif` is compiled but useless on Apple (no bitstream path).
  `ao_audiounit` **already** sets AVAudioSessionCategoryPlayback /
  MoviePlayback / active, and calls
  `setPreferredOutputNumberOfChannels(MIN(deviceMax, requested))` — the
  device max reflecting the real HDMI/eARC route (mpv source,
  ao_audiounit.m init_audiounit).
- **Android media_kit libmpv.so**: `ao_audiotrack` present, `audio-spdif`
  option present, spdif decode wrapper present. mpv's audiotrack ao
  resolves ENCODING_AC3/E_AC3/DTS via JNI at runtime — bitstream
  passthrough is genuinely available where the device route supports it.
  media_kit pins `ao=opensles` by default (media_kit_patched real.dart:2364)
  and **opensles has no passthrough** — any passthrough mode must switch to
  `audiotrack,opensles`, exactly as the existing system-audio-effects
  setting already does.
- **macOS media_kit Mpv.framework**: `ao_coreaudio` with full channel-map
  support — multichannel PCM already works there by default. No
  `coreaudio_exclusive` visible; desktop bitstream is out of scope.

## The three deliverables

### 1. Apple multichannel LPCM (tvOS + iOS) — the everyday win

mpv's default `--audio-channels=auto-safe` collapses to stereo on
audiounit. Setting **`audio-channels=auto`** makes mpv request the track's
real layout, and audiounit's own `MIN(deviceMax, requested)` then caps it
at what the route genuinely carries:

- TV speakers (max 2): auto degrades to stereo by construction.
- AVR/soundbar over HDMI/eARC (max 6/8): a DTS-HD MA / TrueHD / EAC3 5.1
  or 7.1 track decodes to **full multichannel LPCM** — every channel, same
  audio content as the bitstream, minus only the badge on the AVR display.
- AirPlay / Bluetooth / spatial routes: unproven (see rev 2 amendments) —
  which is exactly why this ships opt-in.

Applied through `_configurePlayerAudio` (awaited, pre-open), gated
`PlatformUtil.isTvOS || PlatformUtil.isIosMobile` AND the new opt-in
toggle (rev 2 — see amendments: `auto` is not proven safe on AirPlay/
spatial routes, so the owner validates on real hardware before any
default flip).

### 2. Android Dart-player bitstream passthrough — opt-in

New setting "Audio passthrough (AC3 · EAC3 · DTS core)" — Android only,
default OFF. When enabled, at player init:

1. `ao=audiotrack,opensles` (passthrough needs audiotrack; opensles stays
   as the fallback output exactly like the effects path);
2. `audio-spdif=ac3,eac3,dts`.

The AVR then receives the original bitstream and lights up. Deliberate
choices:

- `dts-hd` (HBR) is NOT in the list — it needs HDMI high-bitrate paths
  that lie about support on enough devices to burn trust; DTS core always
  rides inside DTS-HD anyway. Recorded as a possible "advanced" extension.
- OFF by default because mpv's passthrough is fail-loud, not fail-soft: a
  route that accepts the format claim but can't play it produces silence,
  and only the user knows what their chain supports. Same opt-in philosophy
  (and same settings card) as the system-audio-effects switch.
- Interaction with system-audio-effects: both settings want
  `audiotrack` — compatible; effects on a bitstream track are a silent
  no-op. The property application order (ao first, then spdif) is shared
  through one helper so the two settings cannot fight over `ao`.
- On mpv passthrough init failure mpv does NOT reliably fall back to PCM —
  the setting's caption says so plainly ("if you hear silence, turn this
  off").

### 3. Diagnostics — prove what the pipeline did

The existing one-shot decoder probe gains audio fields (all platforms),
reading the DEVICE side (rev 2):

- `audio_codec=` ← `audio-codec`
- `decoded_channels=` ← `audio-params/channel-count` (decoder side, kept
  separate — it can read 6 while the AO writes 2, which is the very
  downgrade being diagnosed)
- `audio_channels=` ← `audio-out-params/channel-count`
- `audio_format=` ← `audio-out-params/format` (spdif formats surface here
  when passthrough engages, e.g. `spdif-ac3`)
- `ao=` ← `current-ao`

The probe's two-read stability loop extends to `current-ao` +
`audio-out-params/channel-count` so audio isn't sampled before the output
configures. One probe, existing emit channel — a passthrough session
should read `ao=audiotrack audio_format=spdif-ac3`, a tvOS AVR
multichannel session `decoded_channels=6 audio_channels=6`, and today's
downgrade case `decoded_channels=6 audio_channels=2`.

## Explicitly out of scope, documented

- **Apple EAC3/Atmos** (AVSampleBufferAudioRenderer): requires
  `ao_avfoundation`, which requires rebuilding the static libmpv. Recorded
  as the follow-up that would light up "Dolby Atmos" on tvOS for
  EAC3-JOC content. TrueHD Atmos is impossible for third parties on Apple,
  full stop.
- **Desktop passthrough** (wasapi-exclusive / coreaudio-exclusive): niche,
  and the macOS build lacks the exclusive ao anyway. Desktop keeps its
  already-working multichannel PCM.
- **Native Android TV player (Media3) audio**: separate pipeline —
  passthrough there is Media3's own automatic negotiation; verifying and
  hardening it is its own task, not part of the Dart player programme.

## Implementation shape

- One pure helper (`lib/utils/player_audio_config.dart`):
  `audioProperties({required bool passthroughEnabled, required bool
  systemAudioEffects, required bool multichannelEnabled})` (+ platform
  inputs) returning an ORDERED property list — the single owner of `ao`
  (`audiotrack,opensles` when passthrough OR effects needs it), then
  `audio-spdif` (passthrough), then `audio-channels=auto` (Apple, only
  when the multichannel toggle is on). Unit-testable exactly like the
  decode remedy's decisions.
- `_configurePlayerAudio` in `video_player_screen.dart`: reads the three
  preloaded settings, applies the helper's list via awaited `setProperty`
  before the first `open()`, and runs at EVERY player-instance creation
  site (initial + the Android renderer-fallback recreate).
  `_attachAudioEffectSession` keeps only the session-id/broadcast half and
  no longer writes `ao`.
- Storage: `getAudioPassthroughEnabled` + `getAppleMultichannelAudio`
  (+ setters) beside the effects key; both preloaded in the awaited init
  path.
- Settings rows in the Playback Defaults card: passthrough (Android-gated),
  multichannel (tvOS/iOS-gated); settings-search leaves for both.
- Probe fields per the Diagnostics section.

## Tests

- Pure-helper: Apple gets `audio-channels=auto` only with the multichannel
  toggle; Android ao/spdif ordering pinned (ao strictly before spdif),
  present only when enabled, `ao` emitted once when passthrough+effects
  are both on; desktop always empty; stereo/no-toggle = empty everywhere.
- Settings storage round-trip.
- Analyzer + existing suites green; tvOS build compiles.

## Device verification (owner, on return)

- Apple TV → AVR: multichannel track shows `audio_channels=6/8` in the
  probe line and audibly uses the surrounds; TV-speakers route unchanged.
- Android phone/box with the Dart player + passthrough ON over HDMI: AVR
  badge lights for AC3/EAC3/DTS; toggle OFF returns PCM.
- A stereo file anywhere: byte-identical behavior.
