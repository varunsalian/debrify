# Video player end-of-series device checklist

**Pending: no device checks were run during this series.** Phases 1–21 of the
Flutter video-player refactor ran only host tests, the analyzer, structural
checks and release builds with nothing installed or run. Every item below is
pending until a human tester performs it. The device pass and the merge of
`refactor/codebase` into `main` are the user's decisions after the series
(plan L6304–6305).

**Release builds only.** Never install a debug build over a release device: it
wipes the app's data. Use a release build on a dedicated test device with a
test profile/account, and record the build's commit, artifact origin and
SHA-256. Installation and all device actions belong to the human tester; this
series ran no install, adb, emulator or device commands. Preserve existing
settings and data; compare against the pre-refactor release when an outcome is
unclear.

Source plan: [video-player screen plan](video-player-screen-plan.md). Line
numbers ("plan L…") refer to that file in the `refactor/vplayer-p21b`
worktree at the phase 21b commit 6 (completion audit) tree. If the plan is edited again, locate each source by its
section heading. Precedent:
[TV player device checklist](tv-player-activity-device-checklist.md).

## Pending non-device items

These are recorded for the end of the series and are not device checks.

- [ ] **PRE-1. First GitHub Actions CI run on the pushed final SHA.** GitHub
  Actions has run no job since billing stopped. The new `vplayer-structure`
  job (every push, no gate-message filter) is defined and every step was run
  locally at the final gate; report it as "defined, run locally, first CI run
  pending", never as done. Expected: the first run on the final SHA is green;
  record the SHA and run. (P21 §6 CI structure job, plan L6081–6101; P21 §6
  completion wording, plan L6169–6173)
- [ ] **PRE-2. Make `vplayer-structure` a required check on `main`.** This is a
  repository setting and the user's action. (P21 §6 CI structure job, plan
  L6096–6101)
- [ ] **PRE-3. tvOS, Windows and Linux compilation.** These build only in their
  CI/VM pipelines and are recorded as pending. The series' final checks
  (commit 7, run by the user) build only on the Mac: `flutter build apk
  --release`, `flutter build macos --release` and `flutter build ios --release
  --no-codesign`, with nothing installed or run.
  The tvOS, Windows and Linux sessions below need an artifact from those
  pipelines. (P21 §6 final checks, plan L6289–6294; review P3-6, plan L13313)

## How to use this checklist

- Run one session per platform: Android phone (AP), Android TV with the
  Flutter player (ATV), tvOS (TVOS), iOS (IOS), macOS (MAC) and Windows/Linux
  desktop (DSK).
- Part A holds items the plan states for several platforms or for no
  particular platform. Each carries a **Run on** tag. "TV" in a source with no
  further qualification means both Android TV (Flutter player) and tvOS;
  "desktop" means macOS, Windows and Linux. **any** means the source names no
  platform: run it in at least one session where the feature exists, and
  record which. Each platform session's second item says which Part A items to
  run there.
- Record pass, fail or pending for each item and variant. A missing sample,
  provider or hardware capability stays pending with the reason. Where the plan
  pins an original defect, the expected result is the recorded behaviour, not
  a fix: record what happens and attach reproducible regressions as
  follow-ups. This structural series authorizes no fixes.
- Prepare samples: a movie and a multi-season series (with a pack missing an
  episode), a movie collection, debrid/torrent/direct/PikPak (including cold
  storage)/TorBox/YouTube/protected sources, a dead first source, embedded,
  addon, external and bitmap (PGS) subtitles, a mistimed external subtitle,
  Trakt/Simkl/MDBList test accounts, an IPTV provider with categories, EPG,
  Xtream catch-up and recording, a Stremio IPTV channel with failing first
  candidates, Debrify TV and Stremio TV channels, and an AVR for passthrough.

### Not device questions (recorded so they are not re-added)

- P21 mutation points 214, 221, 363 and 367 (television focus hand-backs) were
  reclassified at Step 0b as **not** device questions: they are masked by
  Flutter's own focus handling, which is the same on a device. (Follow-ups §P21
  Step 0, plan L6373–6377; P21a Step 0b Progress, plan L12123, L12159–12160)
- P20 TV post-frame focus re-check (points 28–31, R07) was re-dispositioned
  from device-pending to equivalent at P20 Step 0b. (P20 Step 0 Progress, plan
  L11523–11525, L11593–11595; P20 Step 0b Progress, plan L11671–11677)
- The skip-segment unavailable-provider branch is web-only ("web-pending"),
  and no web session is part of this checklist. (P3 body, plan L876–879)

## Part A — shared items

### Playback basics, sleep, skip, aspect and speed

- [ ] **ALL-01** Run on: any. Identity search labels are unchanged from the
  pre-refactor release. (P1 §Phase 1 device checklist, plan L597)
- [ ] **ALL-02** Run on: any. Start IPTV catch-up/Start Over while an
  identity/EPG lookup is slow, then cancel: the cancellation still wins over
  the slow lookup. (P1 §Phase 1 device checklist, plan L597)
- [ ] **ALL-03** Run on: any. Resume a plain playlist entry (no TorBox or
  PikPak id): it lands at the saved position. (P1 §Phase 1 device checklist,
  plan L597)
- [ ] **ALL-04** Run on: phone, Android TV, tvOS, desktop. Set a 15 min sleep
  timer: the label counts down minute by minute (the real decrement and
  non-positive branch are device-pending), playback pauses at expiry, the
  position is saved and the next episode does not start. "End of episode"
  stops at EOF. (P2 §Device checklist, plan L747; P2 body, plan L726–730; P2
  Progress, plan L7171–7175)
- [ ] **ALL-05** Run on: any. After a sleep-timer stop, press play: the stop
  clears and playback continues into the next item. (P21 §6 added after review
  P3-7, plan L6233–6234)
- [ ] **ALL-06** Run on: any. Arm a sleep timer on a live IPTV channel whose
  live recovery open is in flight when the sleep pause fires. Expected per the
  host characterization: the latch prevents later recovery attempts; record
  whether the already-issued open resumes playing on the real player. (Follow-
  ups, plan L6698–6700)
- [ ] **ALL-07** Run on: phone, Android TV, tvOS, desktop. On a series with
  skip segments, Skip intro / Skip credits appears, skips to the segment end,
  and on TV the Select key skips. Switching episode does not flash the button.
  (P3 §Device checklist, plan L897; P3 Progress, plan L7315–7316)
- [ ] **ALL-08** Run on: phone, Android TV, tvOS, desktop. Every aspect mode,
  including cinema zoom, visibly changes framing. (P4 §Device checklist, plan
  L1023)
- [ ] **ALL-09** Run on: any. The speed menu changes the rate and the rate
  persists on resume. (P4 §Device checklist, plan L1023)
- [ ] **ALL-10** Run on: any. Screen stays awake while playing and is allowed to
  sleep when paused; note any native wake or decoder power anomaly. (P8 §Device
  checklist, plan L1529; P8 Progress, plan L8276–8280, L8320–8322)

### Trackers, completion and resume

- [ ] **ALL-11** Run on: any. With Trakt connected: start, pause, seek and stop
  a movie and a series episode; it is marked watched above 80 %; progress
  resumes elsewhere. With Trakt disabled: no requests are sent, and seeks
  still release resume. (P5 §Device checklist, plan L1137)
- [ ] **ALL-12** Run on: any. With Simkl and MDBList connected: start, pause,
  seek and stop a movie and an episode; watched at the threshold; progress
  visible elsewhere. Trackers disabled before playback send nothing. Disabling
  one mid-playback behaves as characterized: Simkl and MDBList continue their
  existing session (recorded follow-up). (P6 §Device checklist, plan L1260;
  Follow-ups, plan L6724–6727)
- [ ] **ALL-13** Run on: any. With no tracker connected: a movie past the
  configured threshold shows as watched and leaves Continue Watching; a
  rewatch below it restores it; an episode past its threshold is marked
  finished; "This device" mode marks locally even with trackers on. (P7 §Device
  checklist, plan L1372)
- [ ] **ALL-14** Run on: any. Resume lands at the saved position for movies,
  series episodes, TorBox and PikPak entries, with real decoder/keyframe
  landing; leaving during a slow resume never resets the saved point to 0;
  speed, aspect and subtitle choices restore with the position. (Phase 14
  resume items, held in P15 §Device checklist, plan L2767–2769; P14 Progress,
  plan L9269–9274, L9423–9426)
- [ ] **ALL-15** Run on: any. On a source whose resume seek lands slowly or not
  at all, record the real-time landing verification: three retries polling
  1.5 s, 1.5 s and 3 s, then a final 5 s check, and the write guard settling
  after 30 s. No timing parity is claimed; record what happens. (P14 body, plan
  L2364–2370; P14 Progress, plan L9272–9274, L9423–9425)
- [ ] **ALL-16** Run on: any. Pause, then kill or relaunch the app, then
  resume: playback resumes at the paused position (the `togglePlay`
  checkpoint save). (P21 §6 added after review P3-7, plan L6231–6232)

### Subtitles and tracks

- [ ] **ALL-17** Run on: phone, Android TV, tvOS, desktop. Auto subtitle sync
  on a mistimed external subtitle: the pill announces, the result shows and the
  offset applies (real decoded alignment). The manual sync slider and reset
  work. Subtitle style changes apply live. (P9 §Device checklist, plan L1671;
  P9 Progress, plan L8449–8450)
- [ ] **ALL-18** Run on: any. Selecting embedded, addon and external subtitles
  applies them; a broken subtitle reverts to the previous one with a message;
  the menu reflects the corrected selection; bitmap (PGS) subtitles show.
  (P10 §Device checklist, plan L1784; P10 Progress, plan L8489, L8626–8627)
- [ ] **ALL-19** Run on: any. Remembered audio and subtitle choices return on
  the next episode and the next session; default languages pick correctly;
  forced subtitles show for foreign dialogue (real forced metadata); addon
  subtitles auto-select by priority. (P11 §Device checklist, plan L1912; P11
  Progress, plan L8788–8789)
- [ ] **ALL-20** Run on: any. Temporary subtitle files are cleaned up, and
  track preferences and temp-file cleanup hold across an app restart.
  (P11 §Device checklist, plan L1912; P11 Progress, plan L8768–8770,
  L8788–8789)
- [ ] **ALL-21** Run on: phone, TV, desktop. The player menu: every section
  opens and applies. (P13 §Device checklist, plan L2266)

### IPTV

- [ ] **ALL-22** Run on: phone, Android TV, tvOS. Zap with CH+/CH−/arrows and
  held keys across page and category boundaries. (P15 §Device checklist, plan
  L2770–2771)
- [ ] **ALL-23** Run on: any. Picking a search result in the guide re-anchors
  the ring to its category. (P15 §Device checklist, plan L2771–2772)
- [ ] **ALL-24** Run on: any. Start Over and archived replay on an Xtream
  source with catch-up, then return to live. (P15 §Device checklist, plan
  L2772–2773)
- [ ] **ALL-25** Run on: any. Stremio IPTV channel: the candidate ladder
  (failing first candidates) reaches a playable one; a manual source pick
  works. (P15 §Device checklist, plan L2773–2774)
- [ ] **ALL-26** Run on: any. A dropped stream shows the reconnect pill and
  then the surrender snackbar with Retry. (P15 §Device checklist, plan
  L2774–2775)
- [ ] **ALL-27** Run on: any. A series audio language carries across episodes
  and sessions; "start on last channel" re-tunes the last channel that
  actually played. (P15 §Device checklist, plan L2775–2777)
- [ ] **ALL-28** Run on: any. The zap banner floats, fades, hands off to the
  dock, and its countdown ticks while paused. On an archive channel, record
  when the banner's 60 s archive retry refresh fires (exact 60-versus-61 s
  discrimination is device-pending). (P15 §Device checklist, plan L2777–2778;
  P15 body, plan L2743–2747; P15 Progress, plan L9668–9670, L9803–9804,
  L9873–9875)
- [ ] **ALL-29** Run on: any. Live IPTV reconnect (`stream-lavf-o`) and each
  Network & Buffering preset on a real stream; a mixed playlist restores live
  ↔ VOD correctly. (P20 §Device checklist, plan L5113–5119)
- [ ] **ALL-30** Run on: any. The IPTV zap banner and the Debrify TV banner
  vanish instantly when the dock opens. (P21 §6 added after review P3-7, plan
  L6238–6239)

### Startup, sources and episodes

- [ ] **ALL-31** Run on: any. Quick Play with try-next: a dead first source
  shows "Stream unavailable · Trying 2 of N…" and plays the next; a
  debrid-direct first open shows the player surface (no overlay); an
  AIOStreams error slate is skipped; a PikPak startup attempts one torrent
  acquisition; a series pack missing the episode is skipped. (P16 §Device
  checklist, plan L3355–3359)
- [ ] **ALL-32** Run on: any. All sources failed: either "Saved source
  failed…" and the launcher recovers, or "No playable source could be
  started." and the player closes. (P16 §Device checklist, plan L3359–3360)
- [ ] **ALL-33** Run on: phone, TV, desktop. Source sheet via `S` (desktop),
  the dock, DPAD and Back (TV): direct, torrent and pack picks; a dead pick
  restores the previous stream at the same position with the message; a
  YouTube quality switch stays in A/V sync; Load more works. (P16 §Device
  checklist, plan L3360–3363)
- [ ] **ALL-34** Run on: any. Stremio TV slow channel start; a live IPTV source
  pick (the P15 path). (P16 §Device checklist, plan L3365–3366)
- [ ] **ALL-35** Run on: any. On a slow-buffering startup candidate, record the
  buffer-growth extension and the 45 s cap exhaustion (the 45 s is the loop's
  elapsed-time eligibility check, not a whole-operation deadline). (P16 body,
  plan L3280–3283; P16 design review, plan L12795–12799; P16 Progress, plan
  L10024–10025)
- [ ] **ALL-36** Run on: phone, Android TV, tvOS, desktop. Debrify TV: next
  channel from the dock button, the key and the TV remote; the guide opened
  from the dock, from DPAD and from Back-close, then select a channel; a failed
  channel shows the static failure message; the lower-third rises on
  launch/tune/zap, survives a slow resolve (tvOS included) and fades; it hides
  instantly when the dock opens; the progress row is absent with
  `hideSeekbar`; random/percent start on next channel. (P17 §Device checklist,
  plan L3976–3985, L4003)
- [ ] **ALL-37** Run on: phone, Android TV, tvOS, desktop. Stremio TV: switch
  from the guide sheet, with now-playing/next-up updates; "Loading next..." at
  EOF and on Next; the start-at-percent seek lands; sources and the source
  sheet follow the new channel; trackers and subtitles use the new content
  identity. (P17 §Device checklist, plan L3987–3992, L4003)
- [ ] **ALL-38** Run on: phone, Android TV, tvOS, desktop. Catalog series:
  from the guide's full episode list, "Fetching S01E05…" plays an episode
  beyond the pack (pack → episode fetch → pack search); "No playable source
  found for …" appears when nothing resolves; next/prev beyond the pack; a
  single-stream launch opens the guide (synthetic row) and the full episode
  list; late in a direct-link episode, Next starts promptly (prefetch).
  (P17 §Device checklist, plan L3994–4001, L4003)
- [ ] **ALL-39** Run on: any. Press next channel repeatedly during a Debrify TV
  random/percent start and a Stremio TV start-at-percent: record whether the
  start-offset seek lands on a newer channel or a disposed player (a
  characterized original window whose native behaviour is device-pending).
  (P17 body, plan L3815–3820)
- [ ] **ALL-40** Run on: any. Debrify TV Next shows the static overlay "SIGNAL
  ACQUIRED", plus random and percent start. (P18 §Device checklist, plan
  L4405–4406)
- [ ] **ALL-41** Run on: any. The series "next" pop into Quick Play works.
  (The iOS PiP-parked variant is IOS-07.) (P18 §Device checklist, plan L4410)
- [ ] **ALL-42** Run on: any. Title and subtitle lines are correct for a TVMaze
  series, a catalog singleton, Stremio TV and IPTV. (P18 §Device checklist,
  plan L4411–4412)
- [ ] **ALL-43** Run on: any. A PikPak cold-storage start resumes at the saved
  position. (P20 §Device checklist, plan L5120)

### Controls and layout

- [ ] **ALL-44** Run on: every platform. The dock style, palette and size apply
  at launch; the retro static transition shows on next episode and on channel
  switch; the buffering spinner clears on switch. (P21 §6 all platforms, plan
  L6225–6227)
- [ ] **ALL-45** Run on: any platform showing the Debrify channel guide at a
  1280×800 logical viewport. The guide row's name-and-status column
  (`channel_guide.dart:441`) overflows by one pixel under test fonts; check
  whether real fonts clip. (Follow-ups §P21 Step 0, plan L6367–6372)

## Session AP — Android phone

- [ ] **AP-01** Record the device, Android version (API level), test profile,
  release APK commit and SHA-256. (Precedent; P21 §6, plan L6192–6193)
- [ ] **AP-02** Run the Part A items tagged phone, every platform, and the
  **any** items scheduled for this session. (Part A)
- [ ] **AP-03** Random-playback menu tiles render and select. (P1 §Phase 1
  device checklist, plan L597)
- [ ] **AP-04** After a sleep stop, force an Android renderer replacement while
  the resume save is suspended (including the player-created-false path):
  the save completes and the sleep latch prevents auto-resume. (P2 §Device
  checklist, plan L752–754; P2 Progress, plan L7041–7044, L7173–7174)
- [ ] **AP-05** After a sleep stop, trigger Start Over and the background
  playback intent (`e14`): the intent write behaves as before, and the sleep
  latch prevents auto-resume. (P2 §Device checklist, plan L752–754; P2
  Progress, plan L7110–7113)
- [ ] **AP-06** Long-press gives 2× speed; the orientation toggle works; a
  portrait-start seed applies; returning from PiP restores the orientation
  lock. (P4 §Device checklist, plan L1023–1027; P4 body, plan L1017–1020; P4
  Progress, plan L7437)
- [ ] **AP-07** Press Home while playing: PiP auto-enters; the PiP play/pause
  actions work (the `togglePlay` adapter path); returning restores the
  controls. (P8 §Device checklist, plan L1531–1532; P8 M1, plan L1545–1546;
  P8 Progress, plan L8276–8280, L8320–8322; P21 §6 P3-7, plan L6229–6230;
  PiP presentation also pending in P11/P12/P14 Progress, plan L8788, L8883,
  L9425)
- [ ] **AP-08** Background and foreground: playback pauses and resumes
  correctly; an active recording stops on background; record the native
  recording stop order and any renderer recreation. (P8 §Device checklist,
  plan L1532–1533; P8 Progress, plan L8094–8095, L8279–8280)
- [ ] **AP-09** Bitmap (PGS) subtitles: shown on a compatible renderer
  (accepted on `directMediaCodec`), rejected with a message on an incompatible
  Android renderer. (P10 §Device checklist, plan L1786–1789; P10 S2c body,
  plan L1733–1737; P10 Progress, plan L8489)
- [ ] **AP-10** Record whether subtitle auto-sync is offered (the raw
  `supportsSubtitleAutoSync` mobile capability check is device-pending).
  (P9 body, plan L1636–1638; P9 Progress, plan L8390–8391)
- [ ] **AP-11** Identify title: search with the platform keyboard, pick a
  movie, pick a series episode (the dialog appears only when coordinates are
  missing); addon subtitles fetch for the chosen identity; trackers and skip
  keep the launch identity. (P12 §Device checklist, plan L2038; P12 Progress,
  plan L8882–8883, L8944–8946)
- [ ] **AP-12** IPTV recording, Android engine: it survives zaps and player
  closure, saves to the expected place and appears in Recordings. (P13 §Device
  checklist, plan L2268–2272; P13 body, plan L2196–2199; P13 Progress, plan
  L8965–8966)
- [ ] **AP-13** Android recording registry refresh/query (`m2`): the
  Recordings list refreshes after a recording; record native publication and
  any old-query/new-refresh mix-up while zapping to an invalid live channel.
  (P13 Progress, plan L9071–9072, L9089–9091, L9169–9170, L9189, L9199–9200;
  Follow-ups Phase-13 recording windows, plan L6577–6580)
- [ ] **AP-14** With the engine flag on, the Record button state refreshes when
  the bar rises (P21 point 361, Android-only). (P21 §6 P3-7, plan L6237; P21a
  Step 0 Progress, plan L12042–12043; Step 0b, plan L12159–12160)
- [ ] **AP-15** Recording capability probe: on API ≥ 29 the Record button
  shows; on API < 29 it never shows (mark pending without such a device).
  (P20 §Device checklist, plan L5115–5116; P20 Platform seams, plan
  L4981–4986; P20 Progress, plan L11523–11524)
- [ ] **AP-16** PikPak cold-storage reactivation: retry banner, recovery
  mid-delay and exhaustion. (P18 §Device checklist, plan L4403–4404)
- [ ] **AP-17** Shuffle menu and continuous shuffle across EOF; Next and
  Previous on phone controls, including beyond the pack's edge. (P18 §Device
  checklist, plan L4407–4409)
- [ ] **AP-18** Direct Surface renderer rejected: Automatic rebuild keeps the
  resume position, external audio and live channel reconnect. (P19 §Device
  checklist, plan L4764–4765)
- [ ] **AP-19** System audio effects (Wavelet) attach and release; the
  effects preload applies at launch. (P19 §Device checklist, plan L4766; P19
  Progress, plan L11233–11234; P20 §Device checklist, plan L5115–5116)
- [ ] **AP-20** The release-build decoder diagnostic line appears on
  `debrify/player_diagnostics`. (P19 §Device checklist, plan L4770–4771; P19
  Progress, plan L11233)
- [ ] **AP-21** Double-tap left/right seeks ±10 s with the ripple, but not
  inside the top/bottom bands. (P21 §6 phone, plan L6212–6213)
- [ ] **AP-22** Left-half vertical drag sets brightness (where supported),
  right half sets volume, horizontal drag seeks with the HUD. (P21 §6 phone,
  plan L6214–6215)
- [ ] **AP-23** With the styled `two_tier` dock, after rotation and a
  text-scale change, gestures in the dock band are ignored and the skip button
  sits above the dock. (P21 §6 phone, plan L6216–6218)
- [ ] **AP-24** Split-screen and foldable posture changes re-validate the dock
  band (gestures and skip button). (P21 §6 P3-7, plan L6240–6241)

## Session ATV — Android TV (Flutter player)

- [ ] **ATV-01** Record the device, Android version, test profile, release APK
  commit and SHA-256, and that the Flutter player (not the native TV player)
  is in use. (Precedent; P21 §6, plan L6192–6193)
- [ ] **ATV-02** Run the Part A items tagged Android TV, TV, every platform,
  and the **any** items scheduled for this session. (Part A)
- [ ] **ATV-03** Random-playback menu tiles render and select with DPAD.
  (P1 §Phase 1 device checklist, plan L597)
- [ ] **ATV-04** After a sleep stop, force an Android renderer replacement
  while the resume save is suspended: the save completes and the sleep latch
  prevents auto-resume. (P2 §Device checklist, plan L752–754; P2 Progress,
  plan L7041–7044, L7173–7174)
- [ ] **ATV-05** Identify title with the remote: search with the on-screen
  keyboard, pick a movie and a series episode, with correct remote focus
  throughout; addon subtitles follow the chosen identity. (P12 §Device
  checklist, plan L2038; P12 Progress, plan L8882–8883, L8944–8946)
- [ ] **ATV-06** Select audio and subtitle tracks with the remote; choices are
  remembered. (P11 Progress, plan L8768–8770, L8788)
- [ ] **ATV-07** Bitmap (PGS) subtitles on Android TV under the Android-TV
  exemption and on an incompatible renderer: record what shows and any
  message. (P10 §Device checklist, plan L1786–1789; P10 S2c body, plan
  L1733–1737)
- [ ] **ATV-08** IPTV recording, Android engine: survives zaps and player
  closure, saves to the expected place, appears in Recordings; the registry
  refresh/query (`m2`) updates; with the engine flag on, the Record button
  state refreshes when the bar rises (point 361). (P13 §Device checklist, plan
  L2268–2272; P13 Progress, plan L9169–9170, L9189; Follow-ups, plan
  L6577–6580; P21 §6 P3-7, plan L6237; P21a Progress, plan L12159–12160)
- [ ] **ATV-09** Recording capability probe: the Record button shows on API ≥
  29. (P20 §Device checklist, plan L5115–5116)
- [ ] **ATV-10** IPTV timeline toggle: TV focus lands correctly. (P15 body, plan
  L2714–2715)
- [ ] **ATV-11** PikPak cold-storage reactivation: retry banner, recovery
  mid-delay, exhaustion. (P18 §Device checklist, plan L4403–4404)
- [ ] **ATV-12** Shuffle menu and continuous shuffle across EOF with DPAD; Next
  and Previous on TV controls, including beyond the pack's edge. (P18 §Device
  checklist, plan L4407–4409)
- [ ] **ATV-13** Explicit renderer: a Direct Surface failure during a startup
  candidate falls back without advancing the ladder. Record the
  renderer-deferred / already-validated behaviour and native output.
  (P16 §Device checklist, plan L3363–3365; P16 body, plan L3222–3225,
  L3283–3285; P16 Progress, plan L10024–10025)
- [ ] **ATV-14** Direct Surface renderer rejected: Automatic rebuild keeps the
  resume position, external audio and live channel reconnect. (P19 §Device
  checklist, plan L4764–4765)
- [ ] **ATV-15** Renderer replacement during a Stremio IPTV candidate open:
  record whether the probe waits on the old instance until the 12 s timeout
  (characterized, device-pending). (P15 follow-ups, plan L2806–2808)
- [ ] **ATV-16** System audio effects (Wavelet) attach and release; with an AVR,
  toggle passthrough live (AC3/DTS), including rapid double toggles; the
  passthrough and effects preloads apply at launch. (P19 §Device checklist,
  plan L4766–4767; P19 design review P2-2, plan L13145–13151; P19 Progress,
  plan L11233–11234; P20 §Device checklist, plan L5115–5116)
- [ ] **ATV-17** With passthrough on, run subtitle auto-sync and switch audio
  tracks: compressed passthrough stops and re-arms and audio returns; repeat
  with passthrough off. (P9 body, plan L1643–1645; P9 Progress, plan
  L8390–8391, L8449–8450; P9 review, plan L8457–8458)
- [ ] **ATV-18** The release-build decoder diagnostic line appears on
  `debrify/player_diagnostics`. (P19 §Device checklist, plan L4770–4771)
- [ ] **ATV-19** OK toggles and raises the bar; with a skip offered, OK skips.
  DOWN raises the bar; UP opens the session's guide (Debrify TV, Stremio TV,
  IPTV) or raises the bar. (P21 §6 TV, plan L6195–6197)
- [ ] **ATV-20** Holding LEFT/RIGHT enters the cinema scrub on the third repeat
  inside 400 ms (points 317, 318) and accelerates 10/30/60 s; OK commits one
  seek (trackers see one jump); BACK/DOWN cancels and resumes. (P21 §6 TV,
  plan L6198–6200; Follow-ups §P21 Step 0, plan L6373–6375; P21a Progress, plan
  L12042, L12159)
- [ ] **ATV-21** A scrub left open across a source or channel switch never
  seeks the new item; live or `hideSeekbar` sessions never scrub; L/R zaps
  with the bar hidden. (P21 §6 TV, plan L6201–6204)
- [ ] **ATV-22** The bar hides after 3 s of inactivity only while playing,
  stays up while paused, and gets a full interval after a sheet closes.
  (P21 §6 TV, plan L6205–6206)
- [ ] **ATV-23** BACK precedence: scrub, then overlay, then bar, then exit.
  Closing an overlay returns focus to the player root, and the remote is never
  dead. (P21 §6 TV, plan L6207–6210)
- [ ] **ATV-24** BACK walks menu panes and IPTV guide panes before closing, with
  focus kept on the pane. (P21 §6 P3-7, plan L6235–6236)
- [ ] **ATV-25** L/R zap during a stalled IPTV tune with the bar up. (P21 §6
  P3-7, plan L6242)

## Session TVOS — tvOS

- [ ] **TVOS-01** Record the Apple TV model, tvOS version, test profile and the
  release build's commit and provenance (from the tvOS CI pipeline; see PRE-3).
  (P21 §6 final checks, plan L6293–6294)
- [ ] **TVOS-02** Run the Part A items tagged tvOS, TV, every platform, and the
  **any** items scheduled for this session. (Part A)
- [ ] **TVOS-03** Random-playback menu tiles render and select with the remote.
  (P1 §Phase 1 device checklist, plan L597)
- [ ] **TVOS-04** Identify title with the remote and the system keyboard: pick a
  movie and a series episode; addon subtitles follow the chosen identity.
  (P12 §Device checklist, plan L2038; P12 Progress, plan L8944–8946)
- [ ] **TVOS-05** Select audio and subtitle tracks with the remote; choices are
  remembered. (P11 Progress, plan L8788)
- [ ] **TVOS-06** IPTV timeline toggle: TV focus lands correctly. (P15 body,
  plan L2714–2715)
- [ ] **TVOS-07** IPTV recording, TEE: it stops on zap and on player close,
  saves to the expected place and appears in Recordings (native TEE muxing).
  (P13 §Device checklist, plan L2268–2272; P13 Progress, plan L8965)
- [ ] **TVOS-08** 10-bit HDR plays without the blue screen (remedy applied).
  (P19 §Device checklist, plan L4768)
- [ ] **TVOS-09** Content display matching: 24p/HDR mode switch, and the
  boundary clear between items. (P19 §Device checklist, plan L4768–4769; P20
  §Device checklist, plan L5117)
- [ ] **TVOS-10** Route channel count and the software decode override apply.
  (P20 §Device checklist, plan L5117)
- [ ] **TVOS-11** The release-build decoder diagnostic line appears in the tvOS
  console. (P19 §Device checklist, plan L4770–4771)
- [ ] **TVOS-12** Trailer → player handoff without two video outputs, and a slow
  native release (the lease timeout path, real-clock lease label).
  (P19 §Device checklist, plan L4772–4773; P19 Progress, plan L11233–11234)
- [ ] **TVOS-13** OK toggles and raises the bar; with a skip offered, OK skips.
  DOWN raises the bar; UP opens the session's guide or raises the bar.
  (P21 §6 TV, plan L6195–6197)
- [ ] **TVOS-14** Holding LEFT/RIGHT enters the cinema scrub on the third
  repeat inside 400 ms (points 317, 318) and accelerates 10/30/60 s; OK
  commits one seek; BACK/DOWN cancels and resumes. (P21 §6 TV, plan
  L6198–6200; Follow-ups §P21 Step 0, plan L6373–6375)
- [ ] **TVOS-15** A scrub left open across a source or channel switch never
  seeks the new item; live or `hideSeekbar` sessions never scrub; L/R zaps
  with the bar hidden. (P21 §6 TV, plan L6201–6204)
- [ ] **TVOS-16** The bar hides after 3 s of inactivity only while playing,
  stays up while paused, and gets a full interval after a sheet closes.
  (P21 §6 TV, plan L6205–6206)
- [ ] **TVOS-17** BACK precedence (scrub, overlay, bar, exit), including the
  Menu press; closing an overlay returns focus to the player root and the
  remote is never dead. (P21 §6 TV, plan L6207–6210)
- [ ] **TVOS-18** BACK walks menu panes and IPTV guide panes before closing,
  with focus kept on the pane. (P21 §6 P3-7, plan L6235–6236)
- [ ] **TVOS-19** L/R zap during a stalled IPTV tune with the bar up. (P21 §6
  P3-7, plan L6242)

## Session IOS — iOS

- [ ] **IOS-01** Record the device, iOS version, test profile and the release
  build's commit and provenance. (P21 §6 final checks, plan L6291–6292)
- [ ] **IOS-02** Run the Part A items tagged phone, every platform, and the
  **any** items scheduled for this session. The plan's "phone" items do not
  name an operating system; repeat AP-06 (long-press, orientation, portrait
  seed) and AP-21 to AP-23 (gestures, dock band) on an iPhone and record
  them under this session. (P4 §Device checklist, plan L1023; P21 §6 phone,
  plan L6211–6218)
- [ ] **IOS-03** PiP start and stop, and player restore afterwards; the PiP
  play/pause action works (the `togglePlay` adapter path). (P8 §Device
  checklist, plan L1532; P8 Progress, plan L8278–8280, L8320–8321; P21 §6
  P3-7, plan L6229–6230)
- [ ] **IOS-04** Background and foreground: playback pauses and resumes
  correctly; an active recording stops on background. (P8 §Device checklist,
  plan L1532–1533)
- [ ] **IOS-05** After a sleep stop, trigger Start Over and the background
  playback intent (`e14`); the sleep latch prevents auto-resume. (P2 §Device
  checklist, plan L752–754; P2 Progress, plan L7110–7113)
- [ ] **IOS-06** IPTV recording, TEE: it stops on zap and on player close,
  saves to the expected place and appears in Recordings. (P13 §Device
  checklist, plan L2268–2272)
- [ ] **IOS-07** The series "next" pop into Quick Play with iOS PiP parked.
  (P18 §Device checklist, plan L4410)
- [ ] **IOS-08** Record whether subtitle auto-sync is offered (the raw mobile
  capability check is device-pending). (P9 body, plan L1636–1638; P9
  Progress, plan L8390–8391)

## Session MAC — macOS

- [ ] **MAC-01** Record the Mac model, macOS version, test profile and the
  release build's commit and provenance. (P21 §6 final checks, plan
  L6289–6292)
- [ ] **MAC-02** Run the Part A items tagged desktop, every platform, and the
  **any** items scheduled for this session. (Part A)
- [ ] **MAC-03** IPTV recording, desktop capture: it survives zaps and player
  closure, saves to the expected place and appears in Recordings. (P13 §Device
  checklist, plan L2268–2272)
- [ ] **MAC-04** The release-build decoder diagnostic line appears on stdout.
  (P19 §Device checklist, plan L4770–4771)
- [ ] **MAC-05** Mouse movement wakes the controls and the cursor; the cursor
  stays visible under overlays. (P21 §6 desktop, plan L6220–6221)
- [ ] **MAC-06** The keyboard map works: Space, ←/→ seek, ↑/↓ volume with the
  HUD, A, G, C, S, N and media keys. (P21 §6 desktop, plan L6222–6223)
- [ ] **MAC-07** Resizing the window re-validates the dock band (gestures and
  skip button). (P21 §6 P3-7, plan L6240–6241)

## Session DSK — Windows and Linux desktop

Run once on Windows and once on Linux; record each separately.

- [ ] **DSK-01** Record the OS and version, test profile and the release
  build's commit and provenance (from the Windows/Linux CI or VM pipeline;
  see PRE-3). (P21 §6 final checks, plan L6293–6294)
- [ ] **DSK-02** Run the Part A items tagged desktop, every platform, and the
  **any** items scheduled for this session. (Part A)
- [ ] **DSK-03** IPTV recording, desktop capture: it survives zaps and player
  closure, saves to the expected place and appears in Recordings. (P13 §Device
  checklist, plan L2268–2272)
- [ ] **DSK-04** The release-build decoder diagnostic line appears on stdout.
  (P19 §Device checklist, plan L4770–4771)
- [ ] **DSK-05** Mouse movement wakes the controls and the cursor; the cursor
  stays visible under overlays. (P21 §6 desktop, plan L6220–6221)
- [ ] **DSK-06** The keyboard map works: Space, ←/→ seek, ↑/↓ volume with the
  HUD, A, G, C, S, N and media keys. (P21 §6 desktop, plan L6222–6223)
- [ ] **DSK-07** F/F11 and Esc leave fullscreen first, then close the player.
  (P21 §6 desktop, plan L6224)
- [ ] **DSK-08** Resizing the window re-validates the dock band (gestures and
  skip button). (P21 §6 P3-7, plan L6240–6241)

## Source coverage

Every source section and the items that cover it. Phase 14 has no "Device
checklist (end of series)" section of its own: the Phase 14 section (plan
L2274–2409) records only that timeout/retry claims are otherwise
device-pending (L2370). Its resume items open the P15 section (L2765–2767).

| Source | Plan line | Covered by |
| --- | --- | --- |
| P1 §Phase 1 device checklist | L597 | ALL-01, ALL-02, ALL-03, AP-03, ATV-03, TVOS-03 |
| P2 §Device checklist | L747 | ALL-04, AP-04, AP-05, ATV-04, IOS-05 |
| P3 §Device checklist | L897 | ALL-07 |
| P4 §Device checklist | L1023 | ALL-08, ALL-09, AP-06, IOS-02 |
| P5 §Device checklist | L1137 | ALL-11 |
| P6 §Device checklist | L1260 | ALL-12 |
| P7 §Device checklist | L1372 | ALL-13 |
| P8 §Device checklist (and M1, L1546) | L1529 | ALL-10, AP-07, AP-08, IOS-03, IOS-04 |
| P9 §Device checklist | L1671 | ALL-17, AP-10, ATV-17, IOS-08 |
| P10 §Device checklist | L1784 | ALL-18, AP-09, ATV-07 |
| P11 §Device checklist (and M2, L1934) | L1912 | ALL-19, ALL-20, ATV-06, TVOS-05 |
| P12 §Device checklist | L2038 | AP-11, ATV-05, TVOS-04 |
| P13 §Device checklist | L2266 | ALL-21, AP-12, ATV-08, TVOS-07, IOS-06, MAC-03, DSK-03 |
| P14 (no section; body L2370) | L2274 | ALL-14, ALL-15 (via the P15 section and P14 Progress) |
| P15 §Device checklist (holds P14 resume items) | L2765 | ALL-14, ALL-22 to ALL-28, ATV-10, TVOS-06, ATV-15 |
| P16 §Device checklist | L3353 | ALL-31 to ALL-35, ATV-13 |
| P17 §Device checklist | L3974 | ALL-36, ALL-37, ALL-38, ALL-39 |
| P18 §Device checklist | L4401 | ALL-40, ALL-41, ALL-42, AP-16, AP-17, ATV-11, ATV-12, IOS-07 |
| P19 §Device checklist | L4762 | AP-18, AP-19, AP-20, ATV-14, ATV-16, ATV-18, TVOS-08, TVOS-09, TVOS-11, TVOS-12, MAC-04, DSK-04 |
| P20 §Device checklist | L5113 | ALL-29, ALL-43, AP-15, AP-19, ATV-09, ATV-16, TVOS-09, TVOS-10 |
| P21 §6 TV | L6194–6210 | ATV-19 to ATV-23, TVOS-13 to TVOS-17 |
| P21 §6 Phone | L6211–6218 | AP-21, AP-22, AP-23, IOS-02 |
| P21 §6 Desktop | L6219–6224 | MAC-05, MAC-06, DSK-05, DSK-06, DSK-07 |
| P21 §6 All platforms | L6225–6227 | ALL-44 |
| P21 §6 Added after review (P3-7) | L6228–6242 | AP-07, IOS-03 (PiP action); ALL-16; ALL-05; ATV-24, TVOS-18; AP-14, ATV-08; ALL-30; MAC-07, DSK-08, AP-24; ATV-25, TVOS-19 |
| P21 §6 non-device items (CI run, required check, tvOS/Windows/Linux builds, release-build rule, user decisions) | L6081–6101, L6169–6173, L6186–6193, L6289–6305 | PRE-1, PRE-2, PRE-3, header |
| Follow-ups §P21 Step 0: hold-to-scrub 400 ms (317, 318); 214/221/363/367 reclassified | L6373–6377 | ATV-20, TVOS-14; "Not device questions" |
| Follow-ups §P21 Step 0: channel guide row overflow at 1280×800 | L6367–6372 | ALL-45 |
| Follow-ups: Phase-13 recording windows (Android refresh race, native publication) | L6571–6580 | AP-13, ATV-08 |
| Follow-ups: live recovery open before sleep pause ("verify the real native behavior") | L6698–6700 | ALL-06 |
| Follow-ups: Simkl/MDBList continuation after mid-playback disable | L6724–6727 | ALL-12 |
| P15 follow-ups: candidate probe bound to pre-open player (device-pending) | L2806–2808 | ATV-15 |
| P2 Progress: countdown decrement, Android replacement, `e14` intent | L7038–7044, L7108–7113, L7171–7175 | ALL-04, AP-04, AP-05, ATV-04, IOS-05 |
| P3 Progress: classified web/Android paths | L7315–7316 | ALL-07; web-only branch under "Not device questions" |
| P4 Progress: phone portrait/PiP | L7434–7437 | AP-06 |
| P8 Progress: native PiP, recording teardown, wake/decoder power | L8088–8095, L8204–8207, L8276–8280, L8318–8322 | ALL-10, AP-07, AP-08, IOS-03, IOS-04 |
| P9 Progress: DSP/decoded alignment, mobile capability, compressed passthrough stop/rearm | L8387–8391, L8446–8450, L8455–8458 | ALL-17, AP-10, IOS-08, ATV-17 |
| P10 Progress: native bitmap rendering, PiP | L8485–8489, L8623–8627 | ALL-18, AP-09, ATV-07, AP-07 |
| P11 Progress: TV remote selection, preference/temp-file durability, native decoding | L8720–8724, L8766–8770, L8785–8789, L8824–8828 | ALL-19, ALL-20, ATV-06, TVOS-05 |
| P12 Progress: IME/PiP presentation, physical phone/TV focus | L8879–8883, L8941–8946 | AP-11, ATV-05, TVOS-04, AP-07 |
| P13 Progress: Android engine/publication, `m2`, refresh/query, TEE muxing | L8962–8966, L9068–9072, L9086–9091, L9167–9170, L9186–9200 | AP-12, AP-13, ATV-08, TVOS-07 |
| P14 Progress: retry exhaustion, 30 s guard, decoder/keyframe landing, PiP | L9269–9274, L9421–9426 | ALL-14, ALL-15, AP-07 |
| P15 Progress: exact 60-versus-61 s discrimination | L9665–9670, L9800–9804, L9871–9875 | ALL-28 |
| P16 Progress/body/review: native rendering, already-validated state, 45 s cap | L3222–3225, L3280–3285, L10021–10025, L12795–12809 | ALL-35, ATV-13 |
| P17 body: late start-offset seek native behaviour | L3815–3820 | ALL-39 |
| P19 Progress/review: diagnostic channel, effects session, passthrough flip, lease label | L11231–11234, L13143–13151 | AP-19, AP-20, ATV-16, ATV-18, TVOS-12 |
| P20 Progress/body: recording probe, effects/passthrough preloads, TV focus re-check | L4978–4990, L11521–11525, L11593–11595, L11669–11677 | AP-15, AP-19, ATV-09, ATV-16; TV focus under "Not device questions" |
| P21a Progress: 400 ms hold, point 361, reclassifications | L12040–12045, L12123, L12157–12160 | ATV-20, TVOS-14, AP-14, ATV-08 |
| Milestones M3/M4/M5 ("device checks stay on the end-of-series checklist") | L10678, L11038, L11816–11838 | No separate items; their scenarios map to the phase items above |

## Session record

Record each variant separately (platform, skin/dock style, source/provider and
hardware case). A missing sample or capability stays pending.

| Item and variant | Outcome | Evidence or reason pending |
| --- | --- | --- |
| PRE-1 first CI run on the final SHA | pending | GitHub Actions billing stopped. |
| PRE-2 required check on `main` | pending | Repository setting; user's action. |
| PRE-3 tvOS / Windows / Linux builds | pending | CI/VM pipelines only. |
| Release artifacts per platform (commit, origin, SHA-256) | pending | Fill per session. |
| Part A and sessions AP, ATV, TVOS, IOS, MAC, DSK (add a row per tested variant) | pending | No device session was run by this series. |
