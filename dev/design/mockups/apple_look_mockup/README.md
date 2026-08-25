# Spotlight & Showcase — Debrify TV in the Apple TV idiom

Two new TV layouts, drawn at **true panel scale (1920×1080 = 2× the app's logical
pixels)** with real artwork and real metadata.

Open **`index.html`**, click a screen, drive it with the arrow keys.

| Layout | Surface | Becomes |
|--------|---------|---------|
| Spotlight | Home | a new `tv_home_style` value |
| Showcase | Series detail | a new `detail_page_style` value |

Both are additive and picker-gated, exactly like the seven home styles and five
premium detail kinds already in the app. Nothing that ships today changes.

## Where the data comes from

Everything on screen is real, from the two endpoints the app already talks to:

- **Cinemeta** (`v3-cinemeta.strem.io`) — the `top` and `imdbRating` catalogs for
  the shelves and hero, and `/meta/series/tt11198330` for House of the Dragon's
  synopsis, seasons, episode titles/overviews/stills.
- **IMDb GraphQL** (`graphql.imdb.com`) — cast names, characters and headshots,
  via the same query in `lib/services/imdb_enrichment_service.dart`.

**No credential was read.** Both endpoints are public and unauthenticated, and
the app stores no key for either. Simkl and Trakt would only contribute *your*
watch state, which a design mock has no use for, so the token store was left
alone.

## Files

- `index.html` — the built page (artwork + data inlined). This is what you open.
- `index.src.html` — the source, with `__IMG_MAP__` and `__DATA__` tokens.
- `data.json` — the fetched Cinemeta/IMDb payload.
- `art/` — downscaled stills, posters, logos, episode thumbs, cast headshots.
- `inject.py` — bakes `art/` and `data.json` into the source, writes `index.html`.

Rebuild after editing the source:

```
python3 inject.py
```

`fetch.py` (in the session scratchpad) is what produced `art/` and `data.json`;
re-run it only if you want a fresh catalog — the titles rotate.

## What the mock is claiming

1. **The hero is a focusable row.** LEFT/RIGHT pages it, dots show position, and
   it parks where you left it when you come back down. This is the one piece
   that changes Home's **focus topology** rather than its paint — our heroes
   today take their identity from whatever is focused *below* them and have no
   cursor of their own.
2. **Shelves lift over the hero; the hero recedes.** It never scrolls away.
3. **The detail backdrop dissolves into an ambient colour field** lifted off the
   same artwork, while the logo re-forms as a centred header. We already own
   both halves of this — `TvAmbientArtStage` and `utils/dominant_color.dart`.
4. **Caption placement is a rule, not a preference**: inside the card on a
   poster (over a gradient bed), below the card on a 16:9 episode cell. The
   focused episode gets a translucent plate behind the *whole* cell, still and
   text together.
5. **Focus is scale + a white hairline + a large soft shadow.** No colour, no
   glow, anywhere.

## Two things the artwork itself decides

- **Left-third luminance.** Apple's editorial stills keep a clean dark field on
  the left for the identity stack. Metahub backdrops are frame grabs and often
  don't. The mock measures it and **flips the stack to the right edge above
  ~0.32** — page the hero and you can watch it happen. Without this, text lands
  on a face perhaps a third of the time, and no amount of scrim fixes it.
- **Black wordmarks.** Metahub ships some logos as black artwork, invisible on
  ink (the previous mock hit this with Severance). `fetch.py` measures logo
  luminance and anything under `0.30` is dropped to the text-title fallback.

## Findings that change the build

**The Cast & Crew row needs a query change.** `imdb_enrichment_service.dart`
reads `principalCredits` and keeps the `Stars` block — which is three or four
names. That is fine for a "Starring …" line and far too sparse for a row of
portraits. The same endpoint, asked differently, returns a real ensemble:

```graphql
credits(first: 12, filter: {categories: ["cast"]}) {
  edges { node { name { nameText{text} primaryImage{url} }
                 ... on Cast { characters{name} } } } }
```

12 members for Silo, each with a character and a headshot, against 4 from the
`Stars` block. One query, additive — `CastMember` already has both fields.

**House of the Dragon can't lead this layout.** Its metahub logo measures 0.21
luminance — a black wordmark. It was the first choice of detail subject and had
to be swapped for Silo (0.64). The same check disqualified two of the eight hero
candidates. On a logo-led page this is not a rare edge case, it is roughly one
title in four, and the text-title fallback has to be as designed as the logo
path.

## Deliberately not built

Ranked shelves (the giant numerals), hand-curated editorial rows, and the
Dolby/CC/SDH technical badges. All three are *catalogue* features rather than
visual ones — the badges in particular can't be honest on our detail page,
because we don't know a title's audio or HDR until you pick a source.

The tech badges in the Showcase mock are drawn as placeholders to show the
**shape** of that line; the real page would populate it from the chosen source
or omit it.
