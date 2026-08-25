# IPTV Flawless Playback Plan — rev 2 (post-codex review)

> **STATUS 2026-08-12 — BUILT, uncommitted, awaiting device test.**
> Phases 0, 1, 2, 5 fully implemented; Phase 3 partially (TS flags,
> keep-content-on-zap + clear-on-surrender, onStart/background live rejoin —
> chunkless HLS prep and drift detection stay deferred pending device
> telemetry); Phase 4 deferred by design. Verified: Kotlin compiles, Dart
> analyzer clean vs HEAD baseline, 10/10 unit tests on the Dart recovery
> machine (test/iptv_live_recovery_test.dart — the executable spec of the
> episode semantics shared with IptvLiveRecovery.kt), full flutter test suite
> failure set identical to HEAD (onboarding flakes + series_parser are
> pre-existing), fault server endpoints wire-verified with curl.
> Key files: tv/IptvLiveRecovery.kt, tv/IptvTuneDiagnostics.kt,
> video_player/services/iptv_live_recovery.dart + iptv_tune_diagnostics.dart,
> tool/iptv_fault_server.py, wiring in AndroidTvTorrentPlayerActivity.kt +
> video_player_screen.dart.

**Goal:** live IPTV in Debrify should feel like TiviMate — a channel you tune stays up, drops heal invisibly, zaps are fast and never leave a black screen, and the app never parks on a frozen frame pretending to be paused. Both players: native TV (media3/ExoPlayer 1.8.0) and phone/desktop (media_kit/mpv, patched fork).

**Origin:** Discord report (iRRV.2, 2026-08-12): "The live tv pauses… it is only in this app. Tivimate, televizio all work without pausing." Devices: Galaxy Z Fold7 (Dart player) + Google TV Streamer (native TV player). Second symptom: a "paused" channel resumed from the tune-in point instead of the live edge.

**Rev 2:** codex review round 1 (2026-08-12) applied. Material changes: T3 mechanism corrected (it's the phone player's `keep-open` + media_kit replay, not media3 `play()`), P5 deleted (mpv timeout is already 5s, not 60s), retry is now classified + connectivity-aware instead of unconditionally infinite, a post-READY stall detector added (the review's "largest omission"), recovery unified under a generation-owned state machine, Phase 0 (telemetry + fault injection) added, `LiveReconnectingDataSource` deferred until TS-discontinuity-aware, phases made bisectable.

---

## How the reference apps do it (research summary)

- **TiviMate**: big configurable live buffer + hardware decode + silent retry *underneath* the buffer. Recovery happens while the buffer plays through, so the viewer sees nothing. Not flawless either (its ExoPlayer catch-up path rebuffers every 30s — google/ExoPlayer#7859).
- **ExoPlayer's sanctioned mechanism** (team blog "Load error handling in ExoPlayer"): `LoadErrorHandlingPolicy` — load errors retry at the *Loader* level, buffer intact, no player error surfaced. Default ~3 retries; live wants many more, but **classified**: retry transport failures and 408/429/5xx (respect `Retry-After`), do NOT loop on 401/403/404 (dead/expired URL — that needs re-resolve or surrender, not hammering).
- **What `LoadErrorHandlingPolicy` does NOT cover: clean EOF.** A server politely closing a progressive TS connection is not a load error — loader completes, buffer drains, `STATE_ENDED`. ffmpeg names this problem: `reconnect_at_eof`.
- **mpv**: ships `reconnect=1, reconnect_delay_max=7` by default **but not for streamed/non-seekable inputs**. Live IPTV requires `reconnect_streamed=1` (+ `reconnect_on_network_error=1`) via `stream-lavf-o`. Without it, live streams in mpv never reconnect.

---

## Weak-link audit (2026-08-12, branch 0.8.1_alpha; corrected per codex round 1)

### Native TV player — `AndroidTvTorrentPlayerActivity.kt`

| # | Weak link | Where | Effect |
|---|-----------|-------|--------|
| T1 | No `LoadErrorHandlingPolicy` | `setupPlayer` (~:1467) | ~3 default retries then fatal; transient network errors can kill a channel |
| T2 | Live `STATE_ENDED` unhandled | `:761` → `:800` (`nextIptvEpisode()` null for live) | Server-closed stream = frozen frame that looks like a pause. **The reported bug (TV half).** |
| T3 | No live-aware resume from ENDED | `togglePlayPause` `:4511` | `play()` on an ENDED live channel does nothing in media3 1.8.0 (no MediaController in this path — no auto-restart); channel stays frozen. ~~rev-1 claim that it restarts at position 0 was wrong~~ — that symptom belongs to P2b below |
| T4 | `onPlayerError` fall-through is death | `:857-892` | Only HLS re-sniff, behind-live-window, Stremio ladder recover; plain M3U/Xtream mid-stream IO error just stops. NOTE: `isLiveIptvError` at `:864` is really "IPTV player has an error", not "current entry is live" — recovery gating must use `entry.isLive`, never `isIptvMode` |
| T5 | Stall watchdog is Stremio-only, and pre-READY-only | `armIptvStremioStallWatchdog` `:11179` | Plain live channel that never reaches READY spins forever; and NOTHING detects a post-READY wedge (position frozen, playlist stopped updating, bytes stopped, video frames stopped while audio runs) |
| T6 | Stock `DefaultLoadControl` for IPTV | `:1483` (only YouTube customized) | 5s rebuffer-resume threshold. Candidate tune only — dropping it risks play/freeze oscillation on weak links; experiment, don't assume |
| T7 | No `setWakeMode(C.WAKE_MODE_NETWORK)` | builder `:1470` | Wi-Fi power-save can starve a live stream; downloads/recordings take Wi-Fi locks, playback doesn't |
| T8 | Return from Home resumes a stale live stream | `onStop` `:13889` pauses; no live rejoin in `onStart` | Long Home trip → resume far behind live or on a dead connection. Must preserve user-pause intent — lifecycle resume is not play consent |
| T9 | Stock TS extractor flags | no `DefaultExtractorsFactory` config | Mid-GOP joins wait for next IDR; some streams need `FLAG_ALLOW_NON_IDR_KEYFRAMES`/`FLAG_DETECT_ACCESS_UNITS`. CPU cost on low-end boxes — treat as experimental, protocol-scoped |
| T10 | No HLS chunkless preparation | no `HlsMediaSource` config | Slower HLS zaps. Only helps when master playlist carries codec metadata — measure, don't assume |
| T11 | Black flash on zap | no `keepContentOnPlayerReset(true)` | Channel change blanks instead of holding last frame. If adopted: MUST clear on terminal failure or the "old channel frozen under new identity" symptom comes back |
| T12 | No audio focus handling | no `setAudioAttributes(..., true)` | Deliberate trade-off to keep (focus loss would *cause* pauses); documented so nobody "fixes" it casually |
| T13 | No live-latency control | no target-offset/speed control | HLS can drift behind live without ever erroring; progressive TS drifts via long pauses. Needs drift detection → retune |
| T14 | Recovery reopen must carry full identity | `setIptvMediaItem` `:10855` | Any retune must reuse the resolved URL + `currentIptvHttpHeaders`; expired signed/Xtream/Stremio URLs need re-resolve, not blind reopen |

### Phone/desktop player — `video_player_screen.dart` + `packages/media_kit_patched`

| # | Weak link | Where | Effect |
|---|-----------|-------|--------|
| P1 | mpv never reconnects live streams | player creation `:2104` — no `stream-lavf-o` | **The big one.** Any connection close/error = dead channel. mpv's default reconnect excludes streamed inputs |
| P2 | `_onPlaybackEnded` has no live guard | `:3340` | Live EOF walks the episode-advance chain, runs `_markCurrentEpisodeAsFinished()` + scrobble-stop on live, then parks |
| P2b | `keep-open=yes` + media_kit replay-on-play | `real.dart:2347`; media_kit `play()` after completed | Live EOF freezes on last frame (*looks like a pause*); pressing play replays the completed media from its start. **This is the resume-from-tune-in report** (rev 1 wrongly pinned it on media3 T3) |
| P3 | Stream error = snackbar only | `_onIptvStreamError` `:5092` | No retry, black screen stays |
| P4 | Background-return resumes stale live position | `_resumeFromBackground` `:8119` — raw `play()` | Long Home trip on live → minutes behind live edge or dead connection. Must preserve user-pause intent |
| P5 | ~~network-timeout 60s default~~ **WRONG — deleted** | `real.dart:2349` sets `network-timeout=5` already | No change. Do not raise it |
| P6 | No live tune/stall watchdog outside the Stremio ladder | `_tryOpenLiveStream` (12s) is ladder-only | Plain channel that never produces frames = transition overlay forever; no post-READY position watchdog either |
| P7 | Ladder/probe opens drop channel headers | `_tryOpenLiveStream` `:6094` opens `mk.Media(url)` bare | Stremio candidates and any future retry path lose per-channel headers the normal open path carries — reopen-with-full-identity bug already live today |
| P8 | `cache-on-disk=yes` for live sessions | `real.dart:2356` | Long live watching churns disk cache; live-specific cache limits/low-storage handling absent. Investigate live-scoped `cache-on-disk=no` |

---

## Architecture (rev 2)

**One recovery state machine per player, owned by a tune generation.** Every recovery source — clean EOF, fatal error, pre-READY watchdog, post-READY stall detector, lifecycle rejoin, user Retry — feeds the same machine; every scheduled retry carries the generation and is cancelled by zap, exit, `onStop`, user pause, or sleep latch. No two ladders may run at once (Stremio candidate ladder owns recovery for its channels on BOTH players; the generic machine stands down while it's active). All gating uses **`entry.isLive == true`** (TV) / `channel.isLive` (Dart) — never `isIptvMode`, which also covers VOD/catchup/series and would break completion, auto-advance, resume positions, and deliberate finite-stream EOF.

**Layer 1 (invisible):** connection-level retry under an intact buffer — classified `LoadErrorHandlingPolicy` (TV) and ffmpeg reconnect flags (phone). Classification: transport errors + 408/429/5xx retry with backoff (respect `Retry-After`); 401/403/404 escalate immediately to Layer 2's re-resolve/surrender. Connectivity-aware: while the OS reports no validated network, the machine idles (one pending retry, no hammering); on network-validated it retries immediately.

**Layer 2 (short blip, rare):** player-level re-tune for what Layer 1 can't see — clean EOF, fatal errors, stuck HLS playlists, auth-class failures. Backoff 0/1/3/5s capped, ladder resets after ~15s stable playback. Re-tune always reopens the **exact resolved URL + full per-channel headers** (T14/P7); auth-class failures re-resolve first (Xtream/Stremio/signed URLs). Always rejoins the live edge.

**Layer 3 (detection + prevention):** post-READY stall detector (position advance / rendered frames / bytes loaded; audio-only streams and user pause excluded) feeding Layer 2; pre-READY tune watchdog for all live tunes; `WAKE_MODE_NETWORK`; live-drift detection → retune; live-edge rejoin on long background-return that **preserves user-pause intent**.

**Polish:** zap-speed experiments (TS flags, chunkless HLS, last-frame hold) — each measured on device, kept only if it wins.

Deliberately NOT doing (and why):
- **Local proxy/buffer engine** (TiviMate-style): same observable result available without a new moving part.
- **Adjacent-channel prebuffering / parallel players**: decoder + native-memory cost on 1–2GB boxes (see iptv-crash-audit).
- **Audio focus (T12)**: would *introduce* pause sources.
- **Shrinking the live max buffer**: it's the cover that makes Layer 1 invisible.
- **`LiveReconnectingDataSource` (rev-1 Phase 4) — deferred indefinitely**: transparently concatenating raw TS bytes across a reconnect feeds the extractor PID/timestamp discontinuities it may not survive; ffmpeg gets away with `reconnect_at_eof` because its demuxer is discontinuity-tolerant. Only revisit as a TS-aware relay/remuxer, which is a project of its own. Layer 2's fast re-tune is the honest version.
- **Unconditional infinite retry**: hides permanent failures forever and burns CPU/radio on 1s loops. Classified + connectivity-aware + bounded-per-class instead.

---

## Phases (each lands as small bisectable steps, uncommitted per house workflow)

### Phase 0 — Telemetry + fault injection (small, do first)
1. Per-tune diagnostics line (debugPrint/logcat): tune generation, protocol (TS/HLS/stremio), error class + HTTP status, time-to-first-frame, rebuffer count/duration, last position/frame/byte advance, which recovery source fired, final action. This is how every later phase is judged and how provider-vs-app Discord complaints get triaged.
2. Fault-injection harness (dev-only script): a small local live-origin simulator that can do chunked premature close, clean EOF, stalled socket (accept then silence), 401/403/404/429/503, and a stale HLS playlist (stops updating media sequence). `python -m http.server` is NOT it (restarting a finite file server replays byte zero — models nothing live).

### Phase 1 — TV player: live EOF/error resilience (fixes the Streamer half)
Bisectable steps, in order:
1. **Recovery state machine + tune generation** (no behavior change yet: plumbing + cancellation on zap/exit/onStop/pause/sleep-latch).
2. **Live re-tune on `STATE_ENDED` + `onPlayerError` fall-through** (gated `entry.isLive`, via the machine; reopen resolved URL + headers; auth-class → re-resolve). Skips completion side-effects (nothing marked watched, no auto-advance chain).
3. **Live-aware play press**: play on an ended/errored live channel triggers re-tune to live edge.
4. **Classified `LoadErrorHandlingPolicy`** on the media source factory, live-gated via the machine's current entry: transport/5xx/408/429 → extended bounded retries (~1s, honoring Retry-After); 401/403/404 → escalate to machine; non-live keeps defaults.
5. **Connectivity awareness**: network callback pauses/renews the ladder (idle while offline, immediate retry on validated network).
6. **Watchdogs**: generalize pre-READY (20s → one silent re-tune → surrender state), add post-READY stall detector (position/frames/bytes, ~8s window; audio-only aware; user-pause aware).
7. `setWakeMode(C.WAKE_MODE_NETWORK)`.

**Invariants:** re-tune ≠ zap (no zap banner, no startup-channel re-arm — `noteLiveChannelPlaying` already gates on real playback); recording: the in-player tee (`RecordingDataSource`) — verify what a same-URL reopen does to the open recording file before shipping step 2 (a spanned file must be a valid TS; if not, finalize on retune), and the separate `LiveRecordingService` must be untouched by playback retunes; sleep-timer `END_OF_ITEM` latch outranks recovery; Stremio ladder owns its channels (machine stands down while `iptvStremioChannelKey != null`).

### Phase 2 — Phone player: live EOF/error resilience (fixes the Fold7 half)
Bisectable steps:
1. **State machine + generation** (Dart mirror; holds `_iptvSwitchTicket` integration — any zap strands the machine).
2. **ffmpeg reconnect for live opens**: `stream-lavf-o = reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5` set before live opens, cleared for non-live (property is player-global). No `reconnect_at_eof` (teardown-hang risk; Layer 2 covers EOF).
3. **Live guard in `_onPlaybackEnded`**: live → re-tune ladder (reopen with `channel.playbackHeaders`); skip `_markCurrentEpisodeAsFinished` + scrobble-stop for live. Also fixes P2b's replay-from-start: the ended live channel re-tunes to the live edge instead of letting media_kit replay the completed media.
4. **Fix P7 now** (it's a live bug regardless): `_tryOpenLiveStream` gains a headers parameter; Stremio candidate opens carry the channel's headers.
5. **Retry in `_onIptvStreamError`**: machine-owned ladder first; snackbar only on surrender, with Retry action; respects `_iptvErrorsMuted` + ticket.
6. **Live-edge rejoin on background-return** (> ~30s away → re-tune; short trips keep cheap resume; user-pause intent preserved — `_pausedByLifecycle` already encodes it).
7. **Watchdog**: post-open position-advance stall detector for live (mirror of TV's; `network-timeout=5` already covers dead sockets).

**Invariants:** transition overlay shows once per recovery episode, not per attempt; recording stops on media replacement (already true), desktop recording service untouched; `cache-on-disk` live behavior (P8) measured in Phase 4.

### Phase 3 — Zap speed + polish experiments (TV)
Each item is measure-on-device, keep-if-wins (Phase 0 telemetry provides the numbers):
1. TS extractor flags (`FLAG_ALLOW_NON_IDR_KEYFRAMES`, `FLAG_DETECT_ACCESS_UNITS`) — IPTV-scoped; watch CPU on the Mi Box.
2. HLS `setAllowChunklessPreparation(true)` — only wins when masters carry codec info; measure per-provider.
3. `keepContentOnPlayerReset(true)` for IPTV zaps + **mandatory clear on surrender** (else frozen-old-channel returns).
4. `onStart` live rejoin after long background (mirror of Phase 2.6).
5. Rebuffer-resume threshold experiment (5s → 2-3s) — reject if play/freeze oscillation appears on throttled links.
6. Live-drift detection (T13): position vs live edge beyond threshold → quiet retune (progressive); HLS target-offset tuning if drift shows up in telemetry.

### Phase 4 — Phone cache + remaining experiments
1. P8: live-scoped `cache-on-disk=no` (or capped) — measure storage churn on a long live session first.
2. `reconnect_at_eof=1` live-only experiment — only if Phase 2 telemetry still shows visible EOF blips; test zap/exit teardown hard before keeping.

### Phase 5 — Status surface (build alongside Phase 1-2 UI touchpoints, ship after)
1. **Reconnect pill** in both players, zap-banner/dock grammar: appears only when a recovery episode exceeds ~2s ("Reconnecting…", attempt count; "Retry" on surrender). Layer-1 recoveries never show it.
2. Surrender state UX: replaces today's dead black screen / bare snackbar.

**Execution order: 0 → 1 → 2 → 3 → 4 → 5** (5's pill can ride along with 1-2 if convenient). Phase 1 resolves the Streamer report; Phase 2 the Fold7.

---

## Test matrix (per phase; Mi Box + Fold-class phone; Phase-0 simulator)

- Chunked premature close mid-play → Layer 1 heals silently (logcat retry lines, no UI).
- Clean EOF on live → Layer 2 re-tunes to live edge; no restart-from-beginning, no episode-advance, nothing marked watched, no scrobble-stop.
- Stalled socket (accept, then silence) → detector trips within its window, retune.
- 401/403/404 → immediate escalate: re-resolve (Xtream/Stremio) or surrender with pill; NO retry loop.
- 429/503 with `Retry-After` → honored.
- Stale HLS playlist (media sequence stops) → detected → retune.
- Wi-Fi off 10s/60s → ladder idles offline, recovers ≤ cap after network validates.
- Long pause on live, background/Home short + long → rejoin policy; user-pause stays paused.
- Dead URL zap → one silent retry → surrender pill with Retry; zap away cancels cleanly (generation check).
- Provider sweep: Xtream TS, Xtream HLS, extension-less forced-HLS, Stremio addon (ladder ownership intact), catchup/VOD (no live logic leaks: resume, completion, auto-advance unchanged).
- Recording active during drop (tee + LiveRecordingService both) → file validity checked, dock truthful.
- Regression: timeshift pause/resume within buffer unchanged; sleep timer stops stay stopped; VOD/torrent/debrid untouched.

## Codex review round 2 — disposition (2026-08-12, on the built code)

22 findings, 1 blocker. **Fixed (17):** #1 ticket-before-await in
`_switchToIptvChannel` + ticket-pinned direct retunes (blocker); #2 300ms
stale-event debounce, both machines; #3 `_activeMediaUserPaused` in Dart
eligibility; #4 live ENDED on TV always returns (sleep end-of-item keeps its
stop, minus completion side-effects); #5 offline check at fire-time +
cold-start `activeNetwork` init; #6 Dart retune stops recording first; #7 TV
retune finalizes the tee before a same-URL reopen; #8 custom LoadControl
DELETED — 1.8.0's default rebuffer is already 2000ms (audit row T6 was
wrong, built on the old 5000ms default); #9 loader-retry TIME bounded via
errorCount → TIME_UNSET escalation (15×1s transport, 4 rate-limit waits);
#10 `reconnect_on_http_error=5xx` (429 deliberately escalates — comma-list
values can't ride mpv's key-value option safely) + Dart auth heuristic
(401/403/404 in the error string skip the ladder); #11 Dart 20s pre-frame
tune watchdog; #12 position-advance counts as recovery (audio-only); #14
Dart recovery re-switch is quiet (no overlay/banner); #16 renderer fallback
carries `liveStream`; #17 keep-content re-armed on every tune; #19 URL
redaction in both diagnostics (scheme+host+last segment only — Xtream
credentials live in the PATH); #20/#21/#22 fault server (per-tune stale
epoch + visibly-advancing sequence, multi-wrap source fill, true mid-chunk
drop).

**Accepted, not fixed (5), with reasons:** #13 video-wedge-while-audio-runs
stall (needs rendered-frame plumbing into the machine — Phase-3 telemetry
first) — PAID 2026-08-15, see the field-report section below; #14-TV Stremio EOF re-tunes the winner URL rather than re-laddering
(fatal errors DO re-ladder; transient-drop-rewinner is defensible); #15 TV
onStart always resumes playing — that is the TV player's long-standing
contract (`onStart` has always called `play()`); #18 TS-flags/WAKE_MODE
scope (wake-mode benefits all network playback; TS flags harmless on
IPTV VOD); Dart has no connectivity gate (offline retries just fail fast
into the same ladder; Android-only API on the native side).

## Codex review round 1 — disposition (2026-08-12)

Accepted wholesale: post-READY stall detector; classified/bounded/connectivity-aware retry replacing infinite; `entry.isLive` gating mandate; generation-owned unified state machine; reopen-with-full-identity + auth re-resolve; P7 header-drop find; keep-content clear-on-surrender; Phase 0 telemetry + fault injection; `LiveReconnectingDataSource` deferral (TS discontinuity risk); rebuffer-threshold as experiment not assumption; TS-flags CPU caveat; chunkless-prep caveat; test-matrix upgrade; bisectable phase steps; T3/P5 factual corrections (verified in code: `real.dart:2347-2356`).
Kept against review where it conflicts with house decisions: none — no conflicts arose.

## Field report follow-up — video-render stall (2026-08-15)

Finding #13 stopped being theoretical three days after v0.8.1-alpha.1: a
Google TV Streamer (MediaTek MT8696) reporter — the same user whose
"live TV pauses" report drove this plan — hit *frozen video with running
audio* on entering the fullscreen player, while the browse screen's
two-pane preview (stock demux, stock ExoPlayer) played the same channels
perfectly. Diagnosis: strict MediaTek decoders wedge on the mid-GOP joins
that `FLAG_ALLOW_NON_IDR_KEYFRAMES` invites — the codec accepts input and
never emits output. Audio decodes (ffmpeg renderer), audio drives the
position clock, so the stall detector and tune watchdog both stay quiet:
exactly the blind spot #13 named.

Built in response (native player only):

- **`IptvLiveRecovery.onVideoFrames`** — the rendered-frame plumbing #13
  asked for. The 5s progress ticker feeds the video renderer's
  `renderedOutputBufferCount`; a count frozen for 8s (judged from READY)
  while the position clock stays fresh = video-render stall. Disarmed for
  audio-only entries (`videoFormat == null` — zero frames is radio's
  normal) and while a generic episode owns the player.
- **Capped, latching response, not a generic episode** (a "Stream lost"
  surrender pill is wrong while audio is audibly fine): attempt 1 = plain
  re-tune (codec reset heals transient wedges); attempt 2 = re-tune with
  the aggressive TS flags dropped for that URL (`iptvStrictTsUrls`, the
  `iptvHlsForcedUrls` idiom) + reconnect pill; still frozen = latch off,
  audio plays on. Any rendered frame stands the detector down again.
- **Session escalation**: two distinct URLs earning strict = a strict
  device; every later tune starts strict (skips the ~20s dance per
  channel). Strict = pre-0.8.1 stock demux — slower first frame on
  sparse-IDR streams, nothing else lost; the recovery ladder, loader
  policy and lifecycle rejoin all still apply.

Deliberately NOT ported to the Dart/mpv player: mpv content-sniffs and
demuxes through ffmpeg with no aggressive-flags equivalent, so the root
cause can't arise there (the same reporter's Fold7 "works great" is the
field evidence); media_kit exposes no reliable rendered-frame property to
plumb (`estimated-frame-number` derives from time-pos — it would advance
with the audio clock and see nothing); and the Dart machine already has
its own pre-frame open watchdog. Revisit only if a phone/desktop report
ever shows frozen-video-running-audio.

## Sources

- Load error handling in ExoPlayer (ExoPlayer team): https://medium.com/google-exoplayer/load-error-handling-in-exoplayer-488ab6908137
- media3 customization docs: https://developer.android.com/media/media3/exoplayer/customization
- ExoPlayer #5584 (restart live stream on error): https://github.com/google/ExoPlayer/issues/5584
- ExoPlayer #7859 (TiviMate catch-up rebuffering): https://github.com/google/ExoPlayer/issues/7859
- mpv #5793 (reconnect on network stream; `reconnect_streamed` requirement): https://github.com/mpv-player/mpv/issues/5793
- ffmpeg http protocol reconnect options (`reconnect_at_eof`, `reconnect_streamed`, `reconnect_on_network_error`, `reconnect_delay_max`)
- TiviMate buffering behavior (buffer-size-as-cover): https://tivimates.com/fix-tivimate-buffering-issues-full-guide-to-smooth-iptv-streaming-2025/
