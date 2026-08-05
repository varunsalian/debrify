# IPTV Premium — restyle concepts (2026-08-05)

Open `index.html` for the gallery. Successor to `iptv_redesign_mockup/` — that round
picked the layout (the Command Center cockpit now ships unconditionally: rail → guide →
stage, `lib/widgets/iptv/iptv_results_view.dart`); this round is about making it *feel*
expensive. Same skeleton, same feature carry, three different visual languages.

## What was making the previous iterations read "cheap"

- emoji used as icons
- blue→purple gradient fills on chips/buttons
- gold focus outlines
- boxy panels with visible borders everywhere
- saturated navy background + purple glow
- one type size doing everything (no hierarchy moment)

Every concept below bans all six and commits to: one material, ≤1 accent colour with a
fixed semantic meaning (plus REC red), stroke-SVG glyphs, and exactly one signature
element.

## The three concepts

| # | Name | Language | Signature element | Accent |
|---|------|----------|-------------------|--------|
| P1 | First Edition | Editorial: warm ink, Fraunces serif headline, hairline ledger | The on-air programme set like a front-page headline | none (ivory) |
| P2 | Glasshouse | Ambient: focused channel plays full-bleed, UI = floating tinted-glass panes | The page has no background — it has a broadcast | none (white) |
| P3 | Master Control | Instrument: pure black, mono numerals, ticked meters, corner-bracket focus | Per-channel 6-hour timeline strip with amber playhead | amber = time |

## Constraints honoured (from the 2026-08-05 code audit)

- DPAD grammar unchanged: LEFT-cascade guide→rail→app-sidebar, hold-OK favorite/list
  picker, hold-OK-to-hide category, RIGHT→schedule/stage, submit-only search,
  Offstage schedule swap, focus-node identity map, per-list row extents.
- Rail order as shipped: Library (Favorites/Continue/Recordings/Scheduled) → Lists →
  Sources → Addons → Manage sources.
- TV perf rules: no fades, no shimmer, static skeletons; P2 explicitly ships
  tint-not-blur on Android TV (BackdropFilter can't sample the native underlay video).
- "Quality badge" = the resolution string already scraped from channel names
  (`(1080p)` regex) — no new metadata needed.
- Fonts would be bundled in-app (Fraunces / Inter Tight / Space Grotesk / JetBrains
  Mono); mocks pull them from Google Fonts with system fallbacks.
