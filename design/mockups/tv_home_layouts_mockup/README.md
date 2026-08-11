# TV Home layout concepts — five alternatives to Canvas

Interactive mocks for five new Android TV Home layouts, drawn at true TV scale
(1920×1080 = 2× the app's logical pixels) with the real 64px ghost rail.

Open **`index.html`** in a browser, click a screen, and drive it with the arrow
keys — the focus model is the point of each concept. Auto-demo runs until you
press a key.

| # | Concept | Shape |
|---|---------|-------|
| I | Atrium | Vertical split — ink dossier left, art + two-row poster wall right |
| II | Mosaic | Poster grid, no hero; identity in a fixed top band |
| III | Promenade | Full-bleed art, centred identity, centre-locked 16:9 strip |
| IV | Deck | Rounded 16:9 card on ink with the next titles stacked behind |
| V | Tonight | Resume-first dashboard: big continue card + vertical Up Next queue |

## Files

- `index.html` — the built page (artwork inlined as data URIs). This is what you open.
- `index.src.html` — the source, with an `__IMG_MAP__` token where the artwork goes.
- `art/` — downscaled metahub stills, posters and logo art (~1 MB total).
- `inject.py` — base64s `art/` into the token and writes the built page.

Edit `index.src.html`, then rebuild:

```
python3 inject.py          # writes the built page next to the script
```

(The script writes to its own directory; copy the result over `index.html`.)

## Notes

- Metahub's Severance logo is a **black** wordmark — invisible on ink. It's
  excluded from the sample set; worth remembering for the real hero, where the
  text fallback is the safer render for dark logo art.
- Every concept is additive: a new value in `tv_home_style`, a new branch in the
  board build. Canvas stays the default.
