# Merged details page — six layout concepts

Interactive mocks for six alternative layouts of `MergedDetailScreen`
(`lib/screens/merged_series_detail_screen.dart` + `lib/widgets/episodes_panel.dart`),
each drawn at **four screen sizes** from one set of content.

Open **`index.html`**, pick a size, click a screen, and drive it with the arrow
keys — every concept's DPAD model is part of the proposal, not an afterthought.

| # | Concept | Structural axis |
|---|---------|-----------------|
| I | Marquee | Episodes run **horizontally** along the bottom of full-bleed art |
| II | Dossier | **Two independent scroll planes** — a fixed identity card, a pure list |
| III | Broadsheet | **Type-first**, no backdrop; a numbered ledger that opens stills on focus |
| IV | Stage | **Tabs** — 50/50 split, everything the page knows has a home |
| V | Filmstrip | **Episode-centric** — the focused still *is* the page |
| VI | Console | **Action before description** — a big continue card, then the season |

**The same screen serves movies**, so there's a Series / Movie toggle beside the
size switcher. `MergedDetailScreen` drops the episode pane for a movie — and the
episode list is the load-bearing element in five of these six — so each concept
also states what it becomes without one:

| # | Concept | As a movie |
|---|---------|-----------|
| I | Marquee | Clean — the rail becomes More Like This |
| II | Dossier | Clean — the right pane becomes the reference column |
| III | Broadsheet | Strong — the ledger becomes the cast list |
| IV | Stage | Trivial — drop one tab, add Sources |
| V | Filmstrip | **Breaks** — nothing for the strip to be, nothing for focus to drive |
| VI | Console | Clean — hero becomes the movie's resume card, grid becomes More Like This |

Sizes: TV 960×540 (the app's logical TV size) · Desktop 1280×800 ·
Tablet 834×1112 · Phone 390×844. Each frame is its own CSS container, so the
layouts respond to the *frame*, not the browser window — which is what lets four
sizes sit on one page honestly.

## Fidelity to the app

- **Palette is lifted from source**, not invented: ground `#0B0B0E`, episodes
  plane `#0E0B14`, state gold `#F5B942`, focus `#FBBF24` (`HomeTheme.focusGold`),
  IMDb `#F5C518`, Trakt `#ED1C24`, Simkl `#22D3EE` (`tracker_brand_marks.dart`).
- **The per-title accent `#ABA124` was sampled from the real poster** with the
  same most-saturated-pixel rule `extractDominantColor` uses, so it stands in for
  what the app would actually pick for this title.
- **Gold means state, never decoration** — watched ticks, progress, bound
  sources, awards. That rule is load-bearing in the current screen and is kept.
- The focus ring is an **in-bounds foreground border**, matching `_FocusHalo`
  (not a glow — spread shadows bleed through the glass surfaces).
- Every control the real page has is present: Resume/Start Watching with the
  S·E tag, Trailer, bound-sources pill, the neutral ⋯ sheet, both tracker pills
  with live state and rating, season stepper, per-episode ⋮.

## Content

Series: real Breaking Bad season 5 — all 16 episodes with stills, ratings, air
dates and synopses from TVmaze; cast headshots from the same source; backdrop,
logo and poster from metahub. Nothing is lorem, and the season bar's
"16 episodes" is 16 episodes.

Movie: Interstellar — art from metahub, cast headshots from TVmaze's person
records (which exist independently of any show), six real film posters for
More Like This.

## Files

- `index.html` — the built page (all artwork inlined as data URIs). Open this.
- `index.src.html` — source, with `__IMG_MAP__` / `__EPS__` / `__CAST__` /
  `__MCAST__` / `__MRECS__` tokens.
- `data.json` — episode, cast, movie-cast and movie-recommendation metadata.
- `art/` — 52 downscaled images (~1.9 MB).
- `inject.py` — bakes art and data into the tokens and writes `index.html`.

Rebuild after editing the source:

```
python3 inject.py
```

## Notes

- The Artifact CSP blocks every external host, hence the data URIs and the baked
  data. It also blocks font CDNs — so the type system is built on **weight,
  tracking, case and a tabular mono for data** rather than a display webfont the
  Flutter app couldn't ship anyway. Broadsheet is the exception: it uses
  `ui-serif`, which Flutter *can* ship, because that concept is the serif.
- Only Broadsheet is cheap enough to render without artwork — worth remembering
  for the weak TV GPU. Marquee, Stage, Filmstrip and Console all want the
  backdrop layer that Home already pays for.
- **Scrims need a legibility floor, not a look.** Tuned on Breaking Bad's dark
  backdrop they washed out completely over Interstellar's bright sky — the
  identity block sat on 0.3 alpha. Both the gradient stops and the logo's own
  drop-shadow now assume artwork could be anything. Metahub logo art is
  frequently white-on-transparent (and occasionally black, see the Severance
  note in the Home mocks), so type is the safer render when contrast is unknown.
- Filmstrip is the only concept where **focus drives page state** (the still,
  title, meta and synopsis all follow the cursor). That's the interesting part
  and the risky part — on TV it means a repaint per DPAD move.
