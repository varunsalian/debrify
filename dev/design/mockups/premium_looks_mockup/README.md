# Premium Looks — five concepts (2026-08-09)

Open `index.html`. Week 1 of `design/plans/PREMIUM_LOOKS_PLAN.md`, and the gate the
rest of the programme waits on: **approve the five directions before the
vocabulary is extracted from them.**

## The experiment

Every concept renders the **identical DOM** — same rail, same hero, same three
shelves, same focused card, same skeleton row. Only the stylesheet changes,
and `build.py` generates all five from one body string so it stays that way.

That constraint is the whole point. The twenty themes we ship today came from
`detail_themes_mockup/`, which put twenty **palettes** on one identical
layout — and palettes are exactly what we got. Its own header says so: *"all
twenty are rendered on one identical layout — the proof that a token layer is
what was missing rather than more layouts."* The token layer was indeed what
was missing, and we built it; but the mockup only ever asked a colour
question, so the answer only ever contained colour.

This round asks a different question with the same method. It varies the
things a palette cannot reach:

| dimension | what it decides |
|---|---|
| **separation** | how things are told apart — fill, glass, space, or hairline rule |
| **scrim** | how text sits on artwork — gradient, blur band, or solid plate |
| **artwork** | contained / bleed / matted / faded, and whether it is graded |
| **focus** | what the cursor does — ring, scale, lift, invert |
| **motion** | snap, glide or settle |
| **density** | row height, card size, gutters |

**The acceptance test:** view the five with the colours removed (a browser
grayscale filter, or just squint). If they still look like five different
apps, the vocabulary in plan §3 is right. If they collapse into one app in
five tints, we learned it in week one for the cost of a day.

## The five

| # | Look | id | Register | Signature |
|---|------|-----|----------|-----------|
| 1 | **Obsidian Glass** | `glass` | Apple TV+ | Floating tinted-glass panes over the artwork; cold accent; blur band under text |
| 2 | **Deep Field** | `field` | Netflix | No boxes at all — artwork bleeds full-frame, space alone separates, focus scales and blooms |
| 3 | **Warm Room** | `hearth` | lamp-lit living room | Matte warm fills with a lit top edge; artwork fades into the page; amber; unhurried |
| 4 | **Console** | `console` | an instrument | Hairlines, monospace, square, grayscale artwork; focus **inverts** like a terminal |
| 5 | **Midnight Cinema** | `reel` | a projected print | Letterbox bars, grain, warm grade on every image; nothing is in a hurry |

All five are dark, per plan D1 — which is what lets us delete the 241-site
light-ink debt with Broadsheet and Concrete rather than pay it.

Ids deliberately reuse **none** of the twenty existing ones, so a stored old
id can never silently resolve to a new theme (plan §8).

## What is deliberately NOT here

- **Layout.** Same DOM in all five, by construction. Structure belongs to the
  existing pickers (TV home style, discover layout, details layout), and a
  Look bundles those separately (plan D8).
- **Sound and haptics.** Cannot be mocked in a page; specified in plan §3.6.
- **Real motion.** The concepts state their character; the feel is judged on
  the Friday device builds, not here.
- **Idle behaviour.** Plan §3.7.

## Honest caveats on the fidelity

- Artwork is CSS gradients, not real posters — same six fixtures in every
  concept, so grading differences are attributable to the concept.
- `backdrop-filter` in a browser is not `BackdropFilter` in Flutter, and on
  Android TV it will not be used at all: Obsidian Glass ships the **opaque
  recipe** there (plan §3.1). Judge concept 1 on a phone.
- CSS `filter: sepia()/grayscale()` stands in for the
  `Image(color:, colorBlendMode:)` path the plan actually proposes. Whether
  that path is affordable in a scrolling shelf is a **W1 spike benchmark**,
  not a settled question — if it fails, grading is demoted to heroes and
  backdrops only (plan D5).
- Grain is forced to 0 on TV by the existing `grainFor` rule, so the TV
  variant of Midnight Cinema keeps the bars, the grade and the warmth without
  the speckle.

## Regenerating

```
python3 design/mockups/premium_looks_mockup/build.py
```

Edit the `LOOKS` list in `build.py`; never edit the generated HTML, or the
identical-DOM guarantee stops being true.
