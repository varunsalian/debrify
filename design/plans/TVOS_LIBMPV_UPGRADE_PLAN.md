# tvOS libmpv upgrade — plan

Status: **M5 RUNNING ON HARDWARE (2026-08-15).** `ao=avfoundation` is live on
Bedroom, decoding E-AC3 with hardware VideoToolbox video, and sounds correct on
the monitor's speakers. See §4c. **M6 (does it fix Atmos) is still unproven and
still needs a route we do not own.**

Earlier: **M2 + M3 GATES PASSED.** 23 xcframeworks packaged
(97 MB, all `tvos-arm64`), symbol gate green on the *packaged* binary, and
Debrify builds for tvOS against them — a 107 MB `Runner.app` with
`ao_avfoundation` linked into the app binary. M4 (regression on Bedroom) and
M6 (the Atmos question) remain.

Earlier: **M1 GATE PASSED.** `libmpv.a` builds for tvOS at 3.3 MB
with `ao_avfoundation` compiled in (`audiounit avfoundation null`), and all
four §10 HDR symbols survived (`_ra_ctx_vulkan_moltenvk`, `context_moltenvk.m`,
`_vt_pl_init`, `hwdec_vt_pl.m`). It took 19 fixes — see §4b. M2 onward is
planned, not proven.

**It compiles and links. That is all that is proven.** `ao_avfoundation` had
never been built for iOS or tvOS by anyone, upstream included, so "the AO
exists upstream, just enable it" understated the work and overstated the
confidence.

Revision 3. Rev 2 added four missing risks (carried patches, ffigen binding
coupling, LGPL redistribution, CI) and proposed a minimal v0.38.0 bump. Rev 3
reverses that target to **v0.41.0**: the AO's commit history shows v0.38.0
predates its EOF handling and blocking-read fixes, so minimising drift would
have shipped the least-complete version of the component being adopted.

Goal: replace the tvOS libmpv with a current build so `ao_avfoundation`
exists, then select it — because the only audio output in today's binary goes
silent on Dolby Atmos routes.

Written in the same spirit as `TVOS_PORT_PLAN.md`: where something is
unverified it says so.

---

## 1. What is actually established

**The bug reproduces on a user's device, restart-controlled.** ZeroDrek,
Apple TV 4K 3rd gen (A2843), receiver over HDMI, Audio Format `Auto`:

| Configuration | Result |
|---|---|
| Auto + **Dolby Atmos on** | **silent** |
| Auto + Dolby Atmos off, app restarted | sound |
| Stereo Only | sound |
| Dolby Digital 5.1 (Bedroom, monitor) | sound |
| AirPods / Bluetooth (Bedroom) | sound |
| Any external player, Atmos on | sound |

His first "Atmos off works" report was a false positive — audio was still
playing from a session that came up healthy. `ao_audiounit` configures the
session once at player init, so a route change mid-session changes nothing.
**Every test of this bug requires a full app restart.** The 10:43 restart-
controlled result is the valid one. A second reporter (Forrest Powers) has the
same symptom, setup not yet confirmed.

**Only one audio output exists in the shipped binary.**
`AUDIO_FIDELITY_PLAN.md:38` — tvOS static libmpv (karelrooted) has
`ao_audiounit` ONLY, no `ao_avfoundation`. Debrify sets nothing by default:
`PlayerAudioConfig.audioProperties()` returns an empty list on tvOS unless the
opt-in multichannel toggle is on, and Debrify never touches `AVAudioSession`
anywhere — not in `tvos/Runner/AppDelegate.swift`, not from Dart.

**`ao_avfoundation` exists upstream and we predate it.**

- `mpv/audio/out/ao_avfoundation.m`, added **2024-03-16**, built on
  `AVSampleBufferAudioRenderer` + `AVSampleBufferRenderSynchronizer`.
- `meson.options:47` — `option('avfoundation', value: 'auto')`. It compiles
  automatically wherever CoreMedia and AVFoundation exist. **No flag needed.**
- `karelrooted/libmpv v0.0.1-beta` was published **2023-12-15**, three months
  earlier. Our build does not lack the AO because anyone disabled it; the
  source predates it.

**Two corrections to existing assumptions:**

1. `ao.c` registers `audiounit` *before* `avfoundation`, and first-to-init
   wins. A rebuild alone changes nothing — the AO must be selected explicitly.
2. `ao_avfoundation.m:263` hard-rejects SPDIF (`"avfoundation does not support
   SPDIF"`). `AUDIO_FIDELITY_PLAN.md:131` expects this AO to unlock "Apple
   EAC3/Atmos" — **that is wrong**. It is a PCM renderer. This fixes silence;
   it does not produce an Atmos bitstream. There is no passthrough path on
   Apple at all.

## 2. What is hypothesis, not fact

**That `ao_avfoundation` fixes it.** The argument: external players work on
his exact route and use the same `AVSampleBuffer*` stack. That is
circumstantial. Nobody has read `ao=`/`audio_channels=`/`audio_format=` off a
failing MAT route, so the actual failure mode inside `ao_audiounit` is unknown.

The one measurement taken (Bedroom, AirPods, Atmos on) came back completely
healthy — `audio_codec=eac3 decoded_channels=6 audio_channels=2
audio_format=floatp ao=audiounit`. That is **not evidence against the bug**: a
Bluetooth route presents 2 channels and no HDMI link, so it cannot exercise the
branch that differs on an AVR. It does prove mpv already downmixes to stereo by
default, which is why an `audio-channels` stereo pin would be a no-op.

## 3. Why fork the dead repo

|  | `karelrooted/libmpv` | `media-kit/libmpv-darwin-build` |
|---|---|---|
| tvOS | **complete** — `build.sh -p tvos`, `xcrun -sdk appletvos`, 3 tvOS meson cross files | none, ios/iossimulator/macos only |
| Maintained | dead since 2023-12-22, 2 releases, 32 stars | active, v0.7.2 (2026-06-27) |
| Build | plain shell + meson, self-bootstraps brew deps | Nix |
| Deps | git submodules → upstream, bump by pointer | Nix-pinned |

The hard part is tvOS cross-compilation and karelrooted already solved it.
Versions are the easy part. Forking media_kit would mean adding an Apple
platform to a Nix cross setup with no guarantee nixpkgs supports `appletvos`.

Working copy: `~/Documents/Projects/libmpv-tvos-build` (outside the app repo).

## 4. Milestones

Each gate is go/no-go. Stop and reassess rather than pushing through.

**M0 — build unmodified at 2023 pins.** `./build.sh -p tvos` with nothing
changed. Establishes a working baseline and an hour-long read on the toolchain.
*Gate:* does a 2023 source tree compile against Xcode 2026 / tvOS SDK 26.5?
**Failure here is not fatal and may not even be surprising** — a 2023 tree
against a 2026 toolchain is exactly the case newer sources fix. If M0 fails on
toolchain grounds, skip to M1 rather than abandoning; only stop if it fails for
reasons a version bump cannot address.

**M1 — bump `Vendor/mpv` to `v0.41.0`.** The latest *release*, not master.

Revision 2 of this plan said v0.38.0, the earliest release containing
`ao_avfoundation`. **That was wrong**, and the AO's own history says why:

| Date | Change | First release |
|---|---|---|
| 2024-03-16 | initial support | v0.38.0 |
| 2024-03-25 | `set_pause` support | v0.38.0 |
| **2024-04-22** | **blocking `ao_read_data`** | v0.39.0 |
| **2024-04-22** | **EOF handling** | v0.39.0 |
| 2024-06-15 | guard macOS 11.3/12-only features | v0.39.0 |
| 2025-05-17 | memory leak fix | v0.41.0 |

v0.38.0 shipped 2024-04-17, five days before EOF handling landed. Taking it
would adopt the least-complete version of the very component being introduced.
Minimising drift was optimising the wrong variable.

**v0.41.0** (2025-12-21) carries all six fixes. Not master: master is
unreleased, moves under us, and carries no stabilisation — an unacceptable
base for a change we cannot verify on the failing route. Cherry-pick a
post-0.41 commit only if a specific one proves necessary.

Known cost — v0.41.0's dependency floors:

```
libavcodec  >= 60.31.102
libavformat >= 60.16.100
libplacebo  >= 6.338.2
```

Measured against the current pins:

- **ffmpeg: satisfies it.** `LIBAVCODEC_VERSION` is **60.35.100** ≥ 60.31.102.
  v0.41.0 will *not* force an ffmpeg bump — which means the ffmpeg security
  gap stays open unless bumped deliberately (see §9).
- **libplacebo: pinned 2023-12-04, floor is 6.338.2.** Almost certainly needs
  bumping; confirm at build time.

Bump only what v0.41.0 forces; leave everything else alone.

Note: submodules were fetched `--depth 1`, so `Vendor/mpv` must be unshallowed
before a tag is reachable.

*Gate:* `strings Libmpv | grep avfoundation` finds the AO.

**M1b — forward-port the carried patches.** `patch/` holds patches for mpv,
ffmpeg, libplacebo, moltenvk, shaderc, libbluray and samba. Only one touches
mpv — `molten-vk-context.patch` — and it modifies `meson.build`, exactly what
breaks across versions.

**It must be ported, not dropped.** Checked: upstream `video/out/vulkan/` has
`context_mac.m` but **no `context_moltenvk.m`**; the only upstream MoltenVK
reference is `video/out/mac/metal_layer.swift`, which is macOS. There is no
upstream equivalent in v0.41.0.

This patch is the `--wid=<CAMetalLayer*>` + `gpu-context=moltenvk` path, and
`PLAYER_METAL_RENDERER_PLAN.md` is built entirely on it. It is unused today
(the texture layer hardcodes OpenGL), so losing it would break nothing
visible — and would silently delete the foundation of the HDR project. See §10.

*Gate:* all patches apply cleanly; `molten-vk-context.patch` specifically is
ported and its symbols verified present (§10).

**M1c — bump `Vendor/ffmpeg` to `n8.0.3`.** A separate step, after M1/M1b are
green and regression-tested.

v0.41.0 does not force this (current 60.35.100 already clears the floor), so it
is a deliberate move to close the security gap. Target chosen by date:

| Tag | Released | vs mpv v0.41.0 (2025-12-21) |
|---|---|---|
| n8.0 | 2025-08-22 | before — the line mpv 0.41 was built against |
| **n8.0.3** | **2026-06-18** | **point release of that line: security + fixes, API-stable** |
| n8.1 | 2026-03-16 | after — new minor, may deprecate what 0.41 expects |
| n8.1.2 | 2026-06-17 | after |

`n8.0.3` takes nearly all the security benefit while staying on the API mpv
0.41 knows.

**This is deliberately not bundled with M1.** It is a two-major jump
(libavcodec 60 → 62) and `patch/ffmpeg/ffmpeg.patch` is very unlikely to
survive it. Combined with the mpv bump, any breakage would be unattributable;
separated, each has an obvious owner.

*Gate:* builds, and M4 regression passes again.

**M2 — full library set + xcframeworks.** `./xcframework.sh`, sane per-slice
sizes and architectures.
*Gate:* all frameworks the podspec's `OTHER_LDFLAGS` names are produced.

**M3 — integrate.** Host the artifacts (GitHub release on our own repo, asset
names matching what `fetch_frameworks.sh` constructs), point the script at the
new `REPO`/`TAG`, reconcile the podspec link line if the library set changed,
and **update the `tvos` job in `.github/workflows/build.yml`**, which calls the
same script.
*Gate:* Debrify builds for tvOS in CI and installs on Bedroom.

**M4 — regression on everything Bedroom can reach.** A new mpv and ffmpeg move
far more than audio: decode, HDR, 4K output, subtitles, IPTV, seeking,
battery. Bedroom covers all of this *except* the Atmos path.
*Gate:* no regression against 0.8.1-alpha.1 behaviour.

**M5 — select the AO.** `ao=avfoundation,audiounit` in `PlayerAudioConfig` —
a **list**, so mpv falls back to today's AO if the new one fails to init. One
line. Consider gating behind a setting for the first alpha.

**M6 — verify the actual fix.** Requires an Atmos route. Soundbar, or
ZeroDrek. Until this passes, the fix is unconfirmed.

## 4a. M0 result (2026-08-15) — failed on toolchain, as designed

`sh ./build.sh -p tvos` at the 2023 pins, 8 minutes, host macOS 26.4 / Xcode
tvOS SDK 26.5. Note `build.sh` does not propagate exit codes — it returned 0
while failing.

Failure chain, in order:

1. **harfbuzz** — `error: use of undeclared identifier 'sincosf'; did you mean
   '__sincosf'?` 2023 harfbuzz against the tvOS 26.5 SDK.
2. **libplacebo** — `TypeError: expected an Element, not ElementTree` while
   generating `src/vulkan/utils_gen.c`. Its generator against modern Python.
3. **libass** — needs harfbuzz; no `.pc` installed.
4. **ffmpeg** — `configure` aborts: `ERROR: libass >= 0.11.0 not found using
   pkg-config`.
5. **mpv** — falls through to *Homebrew's macOS* ffmpeg 8.1.2 and dies on
   `avcodec_close`, removed in FFmpeg 8.

**Verdict: proceed to M1.** Both root failures (1 and 2) are version-vs-
toolchain incompatibilities that newer releases fix; neither is structural.
M0 still earned its cost — run blind, this contamination would have surfaced
during M1 and been misattributed to the mpv bump.

### Two consequences for M1

**Scope grows.** Bump `harfbuzz` and `libplacebo` alongside mpv — v0.41.0's
`libplacebo >= 6.338.2` floor forced the latter anyway. Expect further
dependencies to need the same treatment; bump reactively, one at a time.

**Fix the pkg-config fallthrough first.** `build.sh:223` sets

```
PKG_CONFIG_LIBDIR="$SCRATCH/$ARCH/lib/pkgconfig:$PKG_DEFAULT_PATH"
```

The trailing `$PKG_DEFAULT_PATH` lets a cross-compile silently resolve against
**host macOS Homebrew libraries** when a cross-built one is missing. That is
what turned "libass failed to build" into "mpv compiled against the wrong
ffmpeg and produced a confusing API error five stages later". Dropping it makes
a missing dependency fail immediately and legibly. Do this before any version
bump, or every later failure will be similarly disguised.

## 4b. M1 result (2026-08-15) — 19 fixes, gate passed

Three categories, and the middle one is the story.

**Version bumps (6).** mpv `ea0e9b74` → **v0.41.0**; ffmpeg 2023-12-03 →
**n8.0.3**; harfbuzz → **14.2.1** (`sincosf` vs SDK 26.5); libplacebo →
**v7.360.1** (Python ElementTree in its Vulkan generator); libpng →
**v1.6.58** (`fp.h`, a Mac OS Classic header); MoltenVK → **v1.4.2**
(`MVKSmallVectorImpl::iterator` vs modern libc++ `std::sort`).

**Build hygiene (10) — this build was never a clean cross-compile.** It
borrowed Homebrew's libpng, libxml2, zlib, Vulkan headers, and in M0 even
Homebrew's *ffmpeg 8* through the pkg-config fallthrough; that is what produced
M0's baffling `avcodec_close` error. Removing the fallthrough forced each
borrowed library into either a real cross-compiled one or an explicit SDK
declaration:

- `PKG_CONFIG_LIBDIR` no longer appends the host path.
- meson needs `-Dpkg_config_path`; it does **not** consult `PKG_CONFIG_LIBDIR`
  for *host* dependencies in a cross build. Without it freetype silently fell
  back to its bundled `libpng-1.6.40` subproject.
- Generate `zlib.pc` / `libxml-2.0.pc` for the SDK's `.tbd` stubs, which ship
  headers but no pkg-config files. `libpng.pc` declares `Requires.private:
  zlib`, so its absence broke resolution entirely.
- GNU libtool installed, exposed via a shim holding **only** `libtoolize` —
  putting libtool's `gnubin` on PATH shadows `libtool` with GNU libtool, and
  shaderc combines archives with Apple `libtool -static`.
- `-DSPIRV_SKIP_EXECUTABLES=ON` — spirv-tools' fuzz/reduce call `system()`,
  unavailable on tvOS.
- MoltenVK: `fetchDependencies --tvos` (its `--all` builds xrOS despite its own
  docs and dies when visionOS is not installed), and the 1.4 `static/` package
  layout.
- tvOS deployment target 13.0 → **17.0**, matching
  `media_kit_libs_tvos_video.podspec`. ffmpeg's `vf_scale_vt.c` needs
  VideoToolbox APIs that are tvOS 16+.
- Dropped `--disable-postproc` (libpostproc removed in ffmpeg 8) and stale
  `Vendor/libass/config.status`.

**Porting work (3) — `ao_avfoundation` had never been built for tvOS.**
Upstream builds it on macOS only, so mpv gates the CoreAudio HAL behind
`HAVE_COREAUDIO || HAVE_AVFOUNDATION` — an assumption that collapses on a
platform with AVFoundation but no HAL. `patch/mpv/avfoundation-tvos.patch`
(~150 lines, 7 files):

- Splits the portable `AudioChannelLayout` helpers `ao_avfoundation` actually
  calls (`ca_get_acl`, `ca_find_standard_layout`, `ca_log_layout`,
  `ca_fill_asbd`) from HAL-only ones (`ca_query_layout`, `ca_init_chmap`,
  `ca_get_active_chmap`, `ca_select_device`, `ca_get_device_list`).
- Drops `.list_devs` (optional; no device enumeration without a HAL) and
  guards `setAudioOutputDeviceUniqueID`, which is
  `API_UNAVAILABLE(ios, tvos, watchos, visionos)`.
- Stops compiling `ao_coreaudio_properties.c` and guards
  `<CoreAudio/HostTime.h>`, whose `mach_absolute_time` fallback exists for
  exactly these platforms.

`molten-vk-context.patch` also needed mpv 0.41's `ra_vk_ctx_params` →
`ra_ctx_params` rename.

### The `|| true` hazard, now demonstrated twice

Every patch applies as `git apply … || true`, so a patch that stops applying is
silently ignored. Both patches I first judged obsolete were load-bearing:
`spirv-tools.patch` strips `system()` calls for tvOS, and `ffmpeg.patch` adds
`kCVPixelBufferMetalCompatibilityKey` — the flag `vt_pl` needs to map
CVPixelBuffers into Metal, i.e. the §10 HDR path. **Read every patch before
concluding it is stale**, and keep M2's symbol gate: a build can succeed with
the MoltenVK context missing and say nothing.

## 4c. M5 result (2026-08-15) — the AO runs, and changes channel behaviour

Same device, same file, twenty minutes apart:

| field | `ao_audiounit` | `ao_avfoundation` |
|---|---|---|
| `decoded_channels` | 6 | 6 |
| **`audio_channels`** | **2** | **6** |
| `audio_format` | floatp | float |

**`ao_audiounit` was downmixing 5.1 to stereo; `ao_avfoundation` hands the
route all six channels** and lets `AVSampleBufferAudioRenderer` do the
rendering. Confirmed audible and correct on the monitor's stereo speakers, so
Apple is downmixing — which is the architecturally right place for it.

### This corrects an earlier conclusion in this plan

§2 states that mpv "already downmixes to stereo by default, which is why an
`audio-channels` stereo pin would be a no-op". That was true **of
`ao_audiounit`**, not of the platform, and the measurement it rested on came
from a 2-channel Bluetooth route. The AO choice, not mpv, was capping the
output.

That makes the Atmos hypothesis *more* plausible rather than less: the failing
case is a multichannel HDMI route, and the AO that goes silent there is the one
that force-downmixes to stereo. Handing the route its native layout through
Apple's own renderer is a different negotiation entirely.

### But it is a wider behaviour change than "fix the silence"

Every tvOS user now gets multichannel where they previously got a stereo
downmix. `AUDIO_FIDELITY_PLAN.md` deliberately made multichannel **opt-in**
(`getAppleMultichannelAudio` defaults false) because "`auto` is not proven safe
on AirPlay/spatial routes". This reaches that outcome without the toggle.

Two consequences to weigh before shipping:

- The Apple multichannel toggle is now close to a no-op on tvOS: the new AO
  already emits the decoded layout without it.
- AirPlay and spatial routes remain unproven, exactly as that plan warned —
  only now they get 6 channels instead of 2.

## 4d. Route-aware channel capping (2026-08-15) — a regression the AO switch caused

Selecting `ao_avfoundation` changed `audio_channels` from 2 to 6, because it
hands the route the file's native layout instead of downmixing like
`ao_audiounit` did. On a **two-channel route that is audibly wrong**: the owner
described AirPods as "too noisy, kind of like I am in a bus" — the LFE-heavy
signature of a 5.1 fold done badly.

That is a regression affecting every Bluetooth listener, not only the Atmos
case being fixed, so it is capped automatically rather than behind a setting:

- New read-only `outputChannelCount` on the existing `debrify/tvlog` channel
  returns `max(currentRoute.outputs.first.channels.count,
  maximumOutputNumberOfChannels)`. It **only reads** the session — no category,
  no activation. The AOs own the session and configuring it underneath them is
  what makes that ownership fragile.
- `PlayerAudioConfig` sets `audio-channels=stereo` when the route reports
  <= 2, and leaves a multichannel route native.
- **0 means unknown and changes nothing.** Capping a real AVR would undo the
  fix, so an unanswered query defers to mpv's default.
- The explicit multichannel opt-in still wins, spelled out in code rather than
  relying on the later `audio-channels=auto` overwriting by list order.

### Measured on Bedroom, same AC-3 5.1 source

| Route | `audio_channels` | Result |
|---|---|---|
| Monitor (HDMI) | 6 native | good |
| AirPods, uncapped | 6 | **bad — the regression** |
| AirPods, capped | 2 | acceptable |
| Second Bluetooth earphone, capped | 2 | good |

Two independent Bluetooth devices report the route identically, so the cap is
not tuned to one pair. The AirPods sounding merely "not that great" at 2
channels tracks that pair rather than the code — a different earphone on the
same build sounds fine, and Bluetooth on Apple TV is AAC over A2DP regardless.

**Still untested: HomePod and AirPlay speakers.** They are not stereo-limited
and may report 6+, so the cap will not engage and they will get the native
layout like an AVR. That is arguably right, and it is exactly the "unproven
spatial route" `AUDIO_FIDELITY_PLAN.md` has warned about throughout.

## 5. Verification gap — read before starting

Two separate claims are being tested, and only one of them needs hardware we
lack:

1. **"The new AO works at all."** That `ao=avfoundation` initialises and plays
   correctly on ordinary routes. **Bedroom can verify this completely** — TV
   speakers, AirPods, DD 5.1. If the AO swap is going to break normal
   playback, we will know without buying anything.
2. **"It fixes Atmos."** Needs an Atmos route. Cannot be tested on any hardware
   we own.

So the gap is narrower than it first appears: the *risky* half — swapping the
audio output under every tvOS user — is fully testable here. What remains
unverifiable is only whether the change achieves its purpose.

**M0–M5 can all succeed without fixing the bug.** Bedroom's monitor advertises
Dolby Digital 5.1 but not Atmos, so no configuration of the hardware we own can
reproduce the failure.

Options, neither exclusive:

- **Atmos soundbar (~$100).** Enables iteration in seconds, full logs, and —
  more important than the audio fix — lets M4 regression-test the Atmos path
  too. Cheapest item in this entire plan.
- **ZeroDrek.** Free, and his AVR is the genuine failing case rather than an
  approximation. But: day-long round trips, and he can only answer "is audio
  back?" — he cannot regression-test a player upgrade. If used, ship the
  in-app diagnostic surface first so he can report `ao=`/`audio_channels=`
  instead of a yes/no.

The blast radius argument decides it: this is not a one-line audio change, it
is a new mpv and ffmpeg under the entire playback stack. Validating that
through a remote tester alone is not sound. Prefer both — soundbar for
iteration and regression, ZeroDrek for final confirmation on real hardware.

Ship as an alpha regardless.

## 6. Risks

| Risk | Notes |
|---|---|
| Version bumps cascade | Largely defused by targeting v0.38.0 (4.5 months) instead of master. gnutls/nettle/gmp, luajit on arm64 and MoltenVK are the usual offenders — and with a minimal bump most of them should not move at all. |
| Carried patches stop applying | `patch/` covers mpv, ffmpeg, libplacebo, moltenvk, shaderc, libbluray, samba. `patch/mpv/molten-vk-context.patch` edits `meson.build`, the most version-sensitive file there is. Check whether it is still needed before porting it. |
| ffigen bindings vs new libmpv | `packages/media_kit_patched/lib/generated/libmpv/bindings.dart` is generated from libmpv headers. The mpv client API is stable and additive, so 0.37→0.38 should be safe — but this is a real coupling, and another argument against jumping to 0.41. Verify `mpv_client_api_version()` after the swap. |
| LGPL redistribution | We become the distributor of our own libmpv build. Keep GPL off (`build.sh -g` false) so it stays LGPL-3.0, and publish the build repo so the relink obligation is satisfiable. The app already ships libmpv, but building it ourselves makes the obligation ours. |
| New mpv changes renderer/decoder behaviour | `lib/services/tvos_decode_remedy.dart` is a two-rung workaround ladder tuned against the 2023 build; the decoder probe likewise. Both may need retuning — or may become unnecessary. |
| Library set drifts | podspec `OTHER_LDFLAGS` and `fetch_frameworks.sh` name an exact 28-framework set. Any change breaks the link. |
| `ao_avfoundation` is young | 2024, far less field use than `audiounit`. The `avfoundation,audiounit` fallback list is the mitigation. |
| Hosting | ~2.7 GB extracted. Artifacts must live on a release we control, since karelrooted is abandoned. |
| **Fix unverifiable** | See §5. |

## 7. Rollback

`fetch_frameworks.sh` pins `REPO` and `TAG`. Reverting those two lines plus the
podspec restores today's binary exactly. The app-side change is one property.
Nothing here touches persisted state or schemas.

## 8. Out of scope

- **Atmos/EAC3 passthrough** — impossible; no SPDIF path on Apple (§1).
- iOS, macOS, Android, desktop — this is the tvOS framework set only.
- The storage/CFPreferences findings in
  `docs/superpowers/reviews/2026-08-14-apple-tv-storage-memory-growth-audit.md`.
- Rewriting the decode remedy ladder unless M4 shows it is now wrong.

## 9. Secondary benefit — and an honest caveat about it

Independent of this bug: the newest platform is pinned to an **abandoned 2023
build** (mpv 2023-12-02, ffmpeg 2023-12-03), and nobody upstream will ever
refresh it. Owning the build removes that standing liability, which is the main
reason this is worth starting before verification hardware exists.

Going to v0.41.0 collects most of it: two years of mpv fixes, and whatever
dependency bumps its floors force.

**ffmpeg is still a separate decision.** If the 2023-12-03 pin satisfies
v0.41.0's `libavcodec >= 60.31.102` floor, it will not be bumped by M1 and the
ffmpeg security gap stays open. Closing it is its own step, with its own
regression pass — bundled with M1, a breakage would be unattributable.

The durable win is the infrastructure: a build we own and can re-run makes
every future bump cheap, where today they are impossible.

## 10. What this rebuild must preserve for HDR

`PLAYER_METAL_RENDERER_PLAN.md` ("Phase 2 — the tvOS native video layer: true
10-bit, HDR, Dolby Vision") is built entirely on capabilities that live in this
binary. Because we now control the build, the cheap move is to guarantee they
survive — the expensive move is discovering later that they did not.

That plan's verified foundations, which this rebuild must still satisfy:

| Symbol / feature | Why it matters |
|---|---|
| `_ra_ctx_vulkan_moltenvk`, `context_moltenvk.m` | the `--wid=<CAMetalLayer*>` + `gpu-context=moltenvk` path |
| `_vt_pl_init`, `hwdec_vt_pl.m` | libplacebo VideoToolbox interop: zero-copy P010/NV12/DV into Vulkan-on-Metal |
| features: `libplacebo`, `vulkan`, `vulkan-interop`, `videotoolbox-pl`, `moltenvk` | the whole gpu-next path |
| shaderc, lcms2 | shader compilation, colour management |

**The MoltenVK context is not upstream.** Verified: mpv v0.41.0's
`video/out/vulkan/` has `context_mac.m` but no `context_moltenvk.m`, and the
only upstream MoltenVK reference is `video/out/mac/metal_layer.swift` (macOS).
It exists here solely because of `patch/mpv/molten-vk-context.patch` — the
MPVKit-lineage patch the Metal plan flags as "not an upstream mpv contract".

Today the texture layer hardcodes `MPV_RENDER_API_TYPE_OPENGL`, so **none of
this is exercised**. Dropping the patch during M1b would break nothing
observable and would quietly delete the HDR project's foundation. Hence M1b's
gate.

### Freebies to bank while we are in here

1. **Port `molten-vk-context.patch` to v0.41.0** (M1b) — not optional.
2. **Add a symbol-verification gate to M2**: `strings` the built `libmpv.a`
   for every row in the table above and fail the milestone if any is missing.
   This is the check that would otherwise be skipped and regretted.
3. **Keep the meson feature set** — `libplacebo`, `vulkan`, `vulkan-interop`,
   `videotoolbox-pl`, `moltenvk`, `shaderc`, `lcms2` all enabled.
4. **libplacebo gets bumped anyway** (v0.41.0's `>= 6.338.2` floor, and M0
   showed the 2023 one no longer builds). That is the tone-mapping engine the
   future Vulkan path uses, so the HDR project starts on a newer one for free.

### What this does *not* deliver

HDR itself. The blocker is app-side — the hardcoded OpenGL render API — and
`PLAYER_METAL_RENDERER_PLAN.md` estimates **2–3 weeks attended** to migrate,
spike-gated, requiring a physical TV at every step. This rebuild only ensures
that project's step 1 is not blocked by the library.

One useful side effect: that plan names "rebuilding/patching libmpv+MoltenVK"
as its contingency if the hardware spike fails. Doing this rebuild now retires
that contingency in advance.

### Reference implementation for the spike — `karelrooted/MPVKit`

`PLAYER_METAL_RENDERER_PLAN.md` calls the MoltenVK context an "MPVKit-lineage
patch" and gates everything on a step-1 hardware spike, because the `wid` path
is "binary-verified but NOT an upstream contract". The same author's Swift
binding shows how they actually drove it —
`Sources/MPVKit/MPVVideoPlayer/MPVMediaPlayer.swift`:

```swift
metalLayer.device = MTLCreateSystemDefaultDevice()!
metalLayer.framebufferOnly = true
mpv_set_option(mpv, "wid", MPV_FORMAT_INT64, &metalLayer)
mpv_set_property_string(mpv, "vo", "gpu-next")
mpv_set_property_string(mpv, "gpu-api", "vulkan")
mpv_set_property_string(mpv, "gpu-context", "moltenvk")
mpv_set_property_string(mpv, "hwdec", "videotoolbox")
```

That confirms the exact property sequence and that the `CAMetalLayer` is passed
**by address as `MPV_FORMAT_INT64`**. It turns "we believe these properties are
right" into "here is the patch author's own usage", which is a real de-risk for
a milestone whose entire purpose is proving that path works.

It does **not** retire the spike. MPVKit targets macOS/iOS/tvOS generally and
there is no evidence it ever ran on an Apple TV. Two further caveats: it dates
from December 2023, so it predates mpv 0.41's `ra_vk_ctx_params` →
`ra_ctx_params` rename forward-ported in M1b; and the repo is as abandoned as
the libmpv one (last pushed 2023-12-24, a single release carrying no assets).
Treat it as documentation, never as a dependency.
