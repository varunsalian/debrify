# debrify_tv_spotlight_mockup

Debrify TV (`lib/screens/magic_tv_screen.dart`) redrawn in the **Spotlight idiom** — the same
ground, type stack and borderless lift focus as `onboarding_mockup/` and
`settings_spotlight_mockup/`, and the shipped `PremiumLooks.spotlight` palette
(`#0D1420` ground, `#151D2A` raised, `#E23D4C` accent, white primary buttons).

Open `index.html` in a browser. The TV frame is **playable**: click it, then arrows move focus,
`Enter` activates, `Backspace` goes back. Moving in the channel rail re-draws the stage beside it.

- Deep-link a screen with a hash: `index.html#s=editor`, `#s=settings`, `#s=import`, `#s=tuning`,
  `#s=empty`, `#s=quickplay` — or use the button row above the frame.
- **Art off / Art on** swaps the up-next plates between the typographic bed (shippable today,
  zero network) and the optional poster layer. §4 of the page states what that layer costs.
- **TV / Phone** switches frames. Phone gets a real phone layout — today every device renders
  `_buildTvGridLayout`.

Drawn at **1920×1080; logical values are ÷2**. Artwork is borrowed from
`../apple_look_mockup/art/` (real Cinemeta stills, already in the repo).

## The shape

A **standing rail** of channels and an **acting stage** beside it, replacing the flat grid.

| | Today | Here |
|---|---|---|
| Channel list | 2/3/4-col grid of `CH n` + name, identical on phone and TV | One rail, one column, health pip, pinned group at the top |
| Favourites | A second, smaller card size in a strip above the grid | A *Pinned* group in the same rail — one card size, no duplication |
| What's in a channel | Nothing until you press Play | A stage: pool depth, **how many match your quality**, which keywords are dead, freshness, and a **sample** of the pool by name |
| Channel actions | Long-press only, hinted after focus | Buttons on the stage, one RIGHT away (long-press still works) |
| ⋮ menu | Import · Add · Delete All · Settings behind a 40px glyph | Import screen and a Settings page; Delete All sits with Import, with its blast radius stated |
| Editor / Quick Play | Dialogs the TV keyboard opens *on top of* | Two fixed bands — the keyboard cannot cover the field |
| Two progress dialogs | Channel creation + cached loading | One *Tuning* surface |
| Focus | 3px accent ring, gradient swap | Text rows invert and lift; art plates lift only. No coloured ring anywhere |

**One press still plays.** OK on a rail row tunes immediately — that fast path does not move.
RIGHT is what opens the stage's secondary actions.

## The point of it

Four numbers already live in `debrify_tv.db` and have never been drawn: pool depth
(`tv_cached_torrents`), cache freshness (`tv_channel_cache_state.fetched_at`), per-keyword yield
(`tv_keyword_stats.total_fetched` — a keyword at zero is *why* a channel is thin) and **how many
titles match your quality filter**. Today you discover that a filter emptied a channel from the
relax-fallback snackbar, *after* pressing Play and waiting. The stage moves that to before the press,
with no network call.

## What the page may not promise — §3

The strip is **inventory, not schedule**. An earlier draft called it *"Up next on this channel"*;
that was a lie, and the code says so in four places:

- `_selectTorrentsForPlayback` ends in `list.shuffle(Random())` (`:1525`) — **there is no next**.
- Whether the provider has a given infohash cached is unknown until it answers.
- Size is a **per-file** rule. RD "hands back a flat list of links with no per-file metadata, so a
  file's size is only knowable AFTER unrestricting it" (`_rdLinkPassesSizeRules`) — the pool row's
  size is the whole torrent.
- Both filters degrade on purpose: a quality filter matching zero returns the **unfiltered** pool
  (`:1428`), and after `_rdSizeRejectionLimit` rejections the size filter is **relaxed for the rest
  of the session** (`:1505`).

So the stage counts **quality only** — that one filter really is applied to the cache before the
shuffle, by the same function call — and the strip is captioned *a sample of the pool · nothing here
is a running order*. Where a promise can't be made, the design offers a choice instead: **OK on a
plate plays that title.** It is the only behaviour on the page that isn't already implemented, and
it is cheap — `_watchWithCachedTorrents` already takes a list, so a single-element list is the
whole change.

`_buildChannelsTab`, `_buildChannelCard`, `_buildKeywordChip`, `_buildOptionChip`,
`_buildEmptyChannelsState` and `_buildNoChannelResultsState` (≈ lines 8924–9560) are unreachable
today — `build()` calls `_buildTvGridLayout` on every device. Delete them before redrawing.

This is a design artifact only; no Flutter code is changed by this folder.
