# Spotlight everywhere — phone, tablet & desktop

The TV Spotlight/Showcase design carried to the other three form factors, for
sign-off before any Dart changes. Open **`index.html`** in a browser.

Art and metadata are reused from `../apple_look_mockup/art/` (real Cinemeta /
IMDb data fetched for the TV mock) — nothing new was downloaded.

## What each frame shows

| Frame | Size (logical) | Idiom |
|---|---|---|
| Phone Home / Detail | 390×844 | Apple-phone: centered identity stack, 24% posters, integrated episode card, season popup |
| Tablet Home / Detail | 1194×834 | TV layout + touch bumps (16% posters, visible kebab) |
| Desktop Home / Detail | 1440×810 | TV proportions verbatim + hover lift, dots, search bar |

## Interactive

- **Search button** (top-right of every Home) → unfolds today's field + Catalog/Keyword toggle
- **Season pill** (phone detail) → anchored popup, Apple's exact idiom
- **Hero dots** → page the hero; it also auto-advances every 6 s
- Desktop cards lift on **hover**; all frames **scroll**

## The decisions this mock encodes

1. Phone hero = ~64% height, centered stack, real Play/Add buttons, dots — not the TV hero cropped.
2. Phone cards = 24.3% width with captions **below** the art; TV keeps its measured 13.5% (pinned by `spotlight_spec_test.dart`).
3. Episode cell on phone = one integrated card (still + eyebrow + title + 3-line synopsis + runtime + kebab) at 62% width.
4. Season control: chips ≥600dp, pill + anchored popup below.
5. Search lives behind a top button on every non-TV form factor; the sheet is today's search UI, restyled.
6. Detail hero art stays the backdrop cover-crop (no portrait key-art source exists in our catalogs); the scrim carries legibility.

The full metric table is at the bottom of the page (`#spec`).
