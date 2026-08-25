# onboarding_mockup

A redesign of first-run onboarding (`lib/widgets/initial_setup_flow.dart`) in the
Spotlight idiom — the same ground, type stack and borderless focus mechanic as
`apple_look_mockup/` and `plan/APPLE_LOOK_PLAN.md`.

Open `index.html` in a browser. The TV frame is **playable**: click it, then
arrows move focus, `Enter` activates, `Backspace` goes back. The letter keys on
the key-entry screen really type into the token echo.

Deep-link a single screen with a hash: `index.html#s=key`, `#s=trackers`,
`#s=import`, … (or use the button row above the frame).

## What it changes

| | Today | Here |
|---|---|---|
| Surface | 560px dialog on a slate gradient, `LegacyThemeBoundary` | Full-screen stage on `#1B1C1C→#1F1D1C`, SF stack |
| Key entry | one field in a scroll view; the TV keyboard lands **on top of it** | field band and keyboard band are fixed siblings — overlap is impossible |
| Key input | typing only | type · **send from phone** (existing remote channel) · paste |
| Progress | none | standing 4-step rail (TV) / segments (phone) |
| Back | integration steps only | every screen, one LEFT away |
| Exit | `PopScope(canPop:false)`, no way out | "Skip — I'll do this later" on screen 1 |
| Engines | bare checkbox list in a 280px scroller | one tile each, with a one-line "what this is"; all on by default; single "Turn all off" |
| Trackers | two near-identical ~800-line screens | one screen, two cards; the picked one becomes the code panel in place |
| Import guide | 5 slides auto-advancing every 5s | static checklist + a live panel beside it |
| Ending | flow just pops | summary of what connected, what was skipped |

The doc sections below the frames carry the band geometry, the per-screen DPAD
grids and the full rationale table. Drawn at 1920×1080 — **logical values are ÷2**.
