# TV player control bar — premium OTT, DPAD-native

Status: **revised after review, implementing.** For televisions running the
FLUTTER player (Apple TV today; any TV that falls back off the native player).

## Why a new bar rather than adding focus to the existing one

`lib/screens/video_player/widgets/controls.dart` (540 lines) has **no `Focus`,
no `focusNode`, no `autofocus`** and two focusable widgets total — built for
thumbs. Android TV never exposed the gap because it hands playback to the
20,519-line native player with its own DPAD contract. Retrofitting means
rewriting it while one widget serves two contradictory input models. A separate
bar chosen by `PlatformUtil.isTelevision` keeps the touch path **byte-for-byte
unchanged**, which is the explicit constraint.

---

## Contract: match Android TV, deviate only with a reason

The native player is what users already know, so it is the reference
(`android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt`).

**Bar down**
| Key | Action | Source |
|---|---|---|
| OK | **toggle playback AND raise the bar** | Android :4255, :4444 |
| UP | existing precedence: channel guide -> Stremio guide -> playlist; only if none apply, raise the bar | Android :4302 |
| DOWN | raise the bar | — |
| LEFT/RIGHT tap | immediate -+10s | Android :4372 |
| LEFT/RIGHT held (>=3 repeats) | enter **cinema scrub** | Android :4372, :14731 |
| Menu/Back | leave the player | existing |

**Bar up**
| Key | Action |
|---|---|
| DPAD | focus traversal; the progress row scrubs on LEFT/RIGHT |
| OK | activate the focused control |
| Menu/Back | hide the bar, stay in the player |

**Cinema scrub** (Android :4718, :4780) — NOT the idle-commit scheme first
proposed: hold enters scrub, which **pauses playback**, focuses progress and
previews; **OK confirms** (seek, restore prior play state), **Back or DOWN
cancels** (restore position and play state). One seek on confirm, so Trakt/Simkl
seek hooks and resume fire exactly once. Every scrub carries a generation id;
a transition or dispose invalidates it so a late confirm can never seek the
*next* item.

**Subtitles hide while the bar is up** (Android :4479, :4581) via mpv
`sub-visibility`, restored on hide, in a try/catch so a backend without the
property simply keeps subtitles.

**Auto-hide** (Android :587, :4602): never hides while focus is inside the bar,
and only arms while playing. The existing unconditional 3s timer
(`video_player_screen.dart:7846`) is bypassed for TV.

## Removed from scope — the data does not exist

Review confirmed: no buffered-position state (only a buffering bool), no chapter
model, and `_getEnhancedMetadata()` carries rating/runtime/year, **not**
resolution/HDR/audio codec. So: **no buffered fill, no chapter ticks, no format
chips.** Skip segments stay as the existing skip button, not track bands.

## Dynamic gating

- **Progress row is unfocusable** when `duration <= 0` or live — traversal skips
  it entirely rather than focusing a dead control (Android :4764).
- **Live IPTV row** mirrors Android's order (:6569): `Audio · Subs · Aspect |
  CH− · Play/Pause · CH+ | Guide · Record`, no progress, no speed, record only
  when `hasRecord`.
- Controls that don't apply are **omitted, never disabled-and-focusable**.
- While `_isTransitioning`, the bar is inert: no seek, no next, no source
  switching (`_isReady` stays true across switches, so it cannot be the guard).

## Focus lifecycle — explicit, not implied

- The player owns a root `FocusNode` (`_tvRootFocus`). Focus returns to it on:
  bar hide, overlay close, modal sheet pop, transition start, and scrub cancel.
- Bar hidden = `ExcludeFocus`, so DPAD can never land on an invisible control.
- Raising focuses **Play/Pause**.
- First readiness: non-live raises the bar focused; live force-hides
  (`:1944`) and focus goes to the root node.
- OK before ready is ignored.
- Directional edges are explicit: UP from the transport row goes to progress
  (when focusable), DOWN from progress returns to transport, and LEFT/RIGHT at a
  row end stops rather than escaping the scope.

## Back precedence (player-local `PopScope`)

Order: cinema scrub cancels -> open overlay closes -> bar hides -> route pops.
Without this the app-level `PopScope` would pop the player while the bar is up.

## Visual design

TV logical canvas is 960x540 (after the 2x scale in `MaterialApp.builder`), so
these are half their 1080p pixel size.

- **Scrim** ~190 tall, transparent -> #000 88%, slide-up 24px + fade, 220ms
  `easeOutCubic` in / 160ms out.
- **Row 1** episode title 20px w600, show + SxxExx beneath at 13px/70%, armed
  sleep-timer label right-aligned. Display-only, never focusable.
- **Row 2** progress: 4px idle / 8px focused, played fill in
  `colorScheme.primary`, knob only when focused (10px, 2px ring, soft glow),
  `position` left and `-remaining` right in tabular figures. In scrub mode the
  fill and readout follow the preview and a centre pill shows target + delta.
- **Row 3** transport: `Previous · −10 · PLAY/PAUSE (56px) · +10 · Next` then
  `Subtitles · Audio · Sources · Speed · Aspect · Sleep · More`, 44px each,
  18px gaps.
- **Focus affordance:** scale 1.08 over 120ms, fill goes solid white, icon
  inverts, 2px ring + 16px glow, and the **label fades in below only for the
  focused control** — the bar stays clean and always says what you're on.

## Files

**New** `lib/screens/video_player/widgets/tv_controls.dart` — bar, focusable
button, progress row. Self-contained.

**Modified** `lib/screens/video_player_screen.dart` — mount `TvControls` when
`PlatformUtil.isTelevision`; a television block in the key handler; scrub state
with generation ids; `_tvRootFocus`; player-local `PopScope`; TV auto-hide rule;
subtitle hide/restore.

No other files. No new dependencies. Touch bar untouched.

## Exit criteria

Analyzer clean, tests pass, and on the Apple TV: OK toggles playback and raises
the bar with Play/Pause focused; every control reachable and activatable; hold
enters cinema scrub with OK confirm and Back cancel; progress unfocusable on
live; the bar never hides while focused; Back hides then exits; subtitles
restore on hide; and phone/desktop are identical to today.
