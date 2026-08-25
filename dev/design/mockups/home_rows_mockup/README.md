# Home rows — naming & air (phone / tablet / desktop)

**PICKED: D (Pill), built 2026-08-16** — kept small per the pick ("visible but
not occupying space"): 10px type in a hairline chip, intrinsic width capped at
150 so a long addon name ellipsizes inside the pill instead of squeezing the
heading (only the heading flexes — two Flexibles split the row 50/50 and
wrapped "Featured Movies"). Shared widget: `lib/widgets/home/row_tag_pill.dart`,
worn by both the Spotlight shelf titles and the classic `_railHeader`.
Device-verified on the OnePlus; TV shows the same title+pill on its own quiet
heading scale.

Mock: `index.html` (open locally, or https://claude.ai/code/artifact/0bf1c359-1eee-4eca-8c2c-de090684a57e)

## Problem (vs the Apple TV reference, 2026-08-16)

Screenshotted side by side on the OnePlus at matched scroll depth:

- Headings read like debug output — `Cinemeta: Popular` appears twice in a row
  (movies + series share a title), addon name shouted first, catalog second,
  content type nowhere.
- Headings are small and dimmed (19px @ 0.84) where the reference is large,
  full-white and editorial.
- Every catalog card carries a caption repeating the poster's own art.
- Rows are packed; the reference gives each row air and presence.

## The grammar (all devices, TV included)

`<Catalog> <Type>` as the heading, addon demoted to a quiet tag:

| Today | Proposed |
|---|---|
| Cinemeta: Popular | **Popular Movies** · Cinemeta |
| Cinemeta: Popular | **Popular Series** · Cinemeta |
| Streaming Catalogs: Netflix | **Netflix Movies** · Streaming Catalogs |
| Continue Watching · MOVIE | **Continue Watching** · Trakt · Movies |

Guard: if the catalog name already ends in the type word ("New Movies"),
don't append it again.

## Concepts (differ only in where the tag lives)

- **Frame 0 — Today**: for contrast.
- **A — Ledger**: tag at the row's trailing edge. Cleanest heading; can crowd
  long titles on narrow phones.
- **B — Kicker**: eyebrow above the heading. Most editorial; repeats the same
  addon word prominently down the page, +1 line per row.
- **C — Suffix** ← recommended: quiet suffix after the chevron — the house
  "· tag" grammar CW rows already use. Never collides, ellipsizes, reads on
  TV unchanged.
- **D — Pill**: bordered chip. Legible as provenance but puts chrome back on
  a heading whose point is having none.

Shared across A–D (non-TV only): heading 22px w700 @ 0.96, catalog cards
caption-free, posters ~0.30 width (from 0.243), 34px inter-row air.
Captions rule (as BUILT, revised 2026-08-16): catalog, watchlist AND CW rows
none — the mock kept CW captions for the informative "48 min left" case, but
the card model only carries the title, and a title caption under one row on
an otherwise caption-free board read as inconsistency, not information (the
progress bar stays CW's signal). Channel/logo rails (IPTV, Debrify TV,
Stremio TV) and playlists keep names — a logo tile without its name is a
guess.

## Wiring notes

- Baked prefix `'${addon.name}: ${catalog.name}'`: `stremio_service.dart:1929`,
  `search_screen.dart:2212 / 4550 / 5726`.
- Type word: `_sectionTypeLabel()` (search_screen ~15676) moves INTO the title;
  a new addon-tag accessor feeds the tag slot.
- Renders in both paths: Spotlight (`SpotlightShelf` title/tag +
  `_shelfTitle`) and classic `_railHeader(title:, tag:)`.
- TV scope: naming only — scale/captions/spacing changes are `dpad`-gated.
