# IPTV Page + Settings Redesign — Mock Concepts

Open `index.html` for the gallery. Each concept file shows a TV frame (DPAD
grammar, focus states drawn in) and a phone frame, plus its settings
treatment. The player is out of scope — these cover the IPTV page and
settings only.

## Feature inventory the designs must carry (audited 2026-08-02)

**Content & browse**
- Multiple sources: M3U URL / file / Xtream login; default source; per-source
  counts (live / movies / series); refresh (SWR cache + "updated" chip)
- Virtual sources: Favorites (built-in), Continue Watching (`continue://`),
  custom lists (`list://<id>`)
- Xtream content types: Live · Movies (VOD posters, resume bars) · Series
  (merged series page); M3U = live rows
- Categories with counts; global search over the WHOLE source (submit-only,
  worker isolate); channel numbers, logos, groups; quality/4K badges
- EPG: now/next + progress on every row; full day schedule; Xtream catchup
  (REPLAY on archived programmes)

**DVR (new — must be first-class)**
- Record now (in player); background engine captures survive zap/Home/app-kill
- Schedule from EPG (REC tag on future programmes) + manual timer
  (channel + time + duration); scheduled list w/ cancel; 2-capture cap
- Recordings land in Downloads/Debrify/Recordings — NO in-app library yet:
  the redesign should give it a home (design hook, build later)

**TV experience (the priority)**
- Today: left source rail → channel list → live preview "stage" (tuning
  animation, focused-channel info, keycap hints); hold-OK = favorite/list
  picker; in-app keyboard for search; LEFT-only sidebar policy; 1500-channel
  launch window over a 50k SQLite catalog (any design must be virtualizable)
- Startup channel (boot straight into live TV)

**Settings**
- Sources CRUD (add URL/file/Xtream, edit, refresh, default, remove, EPG
  source per playlist), channel lists management, startup channel
  (off / last / pinned + picker), Recording (engine toggle Android-only,
  scheduled recordings + manual schedule), phone single-column + TV two-pane

## The five concepts

| # | Name | One-liner | Optimizes | Risk |
|---|------|-----------|-----------|------|
| 1 | Live Deck | Streaming-app shelves: hero preview + On-Now rails | Discovery, lean-back browse | Hides 50k-channel depth |
| 2 | Grid Guide | Real cable-style timeline grid, record from any cell | Planning + DVR, TV familiarity | Dense; needs careful phone collapse |
| 3 | Command Center | 3-zone cockpit: rail → channels → live stage + schedule | Power use, evolves current UI (lowest risk) | Less "wow", busy on phone |
| 4 | Zapper | Full-bleed live TV IS the page; UI as overlays | "It feels like a TV" | Browse depth buried; always streaming |
| 5 | DVR Hub | Watch · Guide · Library · Scheduled tabs — TiVo identity | The new recording superpowers | DVR framing may overshadow live zapping |

**Recommendation (see index):** ship C3 as the page skeleton, embed C2's grid
as its Guide view, and take C5's Library/Scheduled as sibling destinations —
C1's On-Now shelves become the Home tab's IPTV row treatment, C4 survives as
the existing startup-channel boot mode.
