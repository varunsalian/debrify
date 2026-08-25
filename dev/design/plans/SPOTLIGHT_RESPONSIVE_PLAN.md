# Spotlight & Showcase on phone, tablet and desktop — rev 6

Carrying the TV Spotlight home and Showcase detail to the other three form
factors, per the approved mock in `design/mockups/spotlight_responsive_mockup/`. **Same
language, not the same layout.** Everything lands **uncommitted**.

Rev 2 incorporated the first Codex review (9 majors); rev 3 the second
(4 majors: latched shell state machine, keyword forcing, single-node compact
season band, off-TV style resolution). Rev 4 incorporates the third round
(3 majors), all on the sheet's Back/startup contract — see "Back semantics"
and "Startup ordering" below. Rev 5 (round 4's single major): Back is
routed through the `MainPageBridge` tab-back mechanism instead of a nested
`PopScope`, which would race the root scope in `main.dart`.

## The two axes, and who decides them

- **Metrics tier** — decided by the *board's own width*:
  `compact < 600 ≤ mid < 1100 ≤ wide`. But compact **presentation**
  (centered hero, integrated episode card, season pill) additionally requires
  touch input: a narrow TV keeps the wide presentation with proportionally
  smaller cards, so the DPAD ladder never targets widgets that don't exist.
  `tier = (width < 600 && !dpad) ? compact : (width < 1100 && !dpad) ? mid : wide`.
- **Input** — `dpad` is an explicit constructor parameter on both
  `SpotlightBoard` and `DetailShowcase`, passed by the hosts from
  `widget.isTelevision` / `PlatformUtil.isTelevision`. Width never implies
  input.

Metric tables (the spec for the new tests):

| `_M` token | wide (today, unchanged) | mid | compact |
|---|---|---|---|
| gutter | 4.375% | 4.375% | 4.8% |
| poster | 13.54% | 16% | 24.3% |
| gap | 2.08% | 2.6% | 4.6% |
| radius | 7 (today's hardcode, moved into `_M`) | 8 | 10 |
| row title | w·26/1920 | same formula | fixed 19 |
| caption | w·21/1920, **overlaid** as today | same | fixed 12, **below the art** |
| hero | 100% of board height | 100% | 64% |

| `ShowcaseMetrics` token | wide/mid (today) | compact |
|---|---|---|
| gutter | 4.375% | 4.8% |
| episode cell | 23.75%, caption below | 62%, integrated card |
| episode rail height | `stillH + 108` | `stillH + plate` (plate = fixed 128 as built: eyebrow 10 + title 14.5 + 3×11.5 synopsis + footer + padding) |
| cast circle | 13% | 23% |
| poster (recs) | 13.54% | 24.3% |
| source card | wide keeps the shipped 280×66 / add 150 exactly | 75% width (`srcW`), height stays 66 |
| type ramp | scattered hardcodes, consolidated into the metrics object | fixed 19/15/12/10.5 |

## Step 1 — style loading + gating (`search_screen.dart`)

The predicate work is **three separate questions**, per review:

1. `_spotlightSelected` — the stored style is `spotlight`. Off-TV this
   requires actually *loading* it: `_loadTvHomeStyle()` + the
   `MainPageBridge.tvHomeStyleChanged` claim move out of the
   `if (widget.isTelevision)` block (≈1364) and run for every Home instance.
   The trailer/theater/sidebar listeners in that block stay TV-gated.
2. `_spotlightShellEligible` — off-TV full-bleed shell: `_spotlightSelected
   && !searchMode && !discoverMode && _catalogQuery.isEmpty &&
   !_catalogSearching && _spotlightHero.isNotEmpty` (the hero guard is the
   review's #3 — CW/favourites-only content must not render an empty hero).
3. Board dispatch (≈14196): off-TV, `'spotlight'` dispatches only when shell
   is eligible; otherwise classic — so catalog results always render on the
   classic board even while Spotlight is selected. TV dispatch unchanged.

`_homeBoardMode`/`_homeStyleEffective` are reshaped around those three; every
existing consumer of `_homeBoardMode` is audited and the TV-bound ones
(`MainPageBridge` glass stage, ambient publish at ≈8372 and the
`onAmbient` wiring at ≈5352, sidebar re-entry, chrome dim) get explicit
`isTelevision` guards. `_heroTrailerActive` is **not touched** — desktop
trailers are cut from scope (follow-up), so the TV shell lifecycle it gates
stays TV-only, and the scaffold-transparency read at ≈11833 keeps its meaning.

## Step 2 — the off-TV shell (search preserved): a latched state machine

Four explicit states (review r2 #1/#2), not a derived condition:

- `_spotlightSelected` — the *resolved* style is `spotlight` (Step 1).
- `sheetForced` (derived, not stored) — `_mode == keyword ||
  _searchController.text.isNotEmpty || _catalogQuery.isNotEmpty ||
  _catalogSearching`. This covers the async default-mode restore (≈1844) and
  preserved keyword results (≈1535): both set `_mode = keyword`, so the sheet
  is forced open before first paint of those states.
- `_searchSheetOpen` (stored) — **latches true whenever `sheetForced` becomes
  true**, and when the user taps the search button. It only returns to false
  by explicit close, and the close affordance exists only while
  `!sheetForced` (the blank catalog prompt). Clearing the last character
  therefore never collapses the sheet under a focused field — the field
  cannot unmount while the user is interacting with it.
- Shell branch active — `_spotlightSelected && !searchMode && !discoverMode
  && !isTelevision && _spotlightHero.isNotEmpty`. The branch **survives all
  sheet states**; inside it:
  - sheet visible (`_searchSheetOpen`): today's
    `Column(_buildHeader(), sourcesBar, Expanded(_buildBody()))` under
    `SafeArea(top: true)`, plus the close affordance — the classic layout,
    same widgets, no copies.
  - sheet hidden: `SafeArea(top: false)` +
    `Stack[ Positioned.fill(_buildBody()), search button ]` (button inset by
    `MediaQuery.viewPadding.top`). **`_buildBody()`, not `_buildBoard()`.**
- Board dispatch (≈14196): off-TV `'spotlight'` dispatches only when the
  shell branch is active **and `!_searchSheetOpen`** — so results, keyword
  mode, and the open sheet always get the classic board, and closing the
  sheet is the only way back to the full-bleed hero.
- **Back semantics** (review r3 #1, mechanism per r4): NOT a nested
  `PopScope` — Home lives in the root route, and a vetoed inner pop still
  reaches the root scope's `didPop == false` path (double-back exit arming,
  `main.dart:2690`). Instead the shell registers a **tab back handler**:
  `MainPageBridge.registerTabBackHandler('home', ...)` in initState /
  unregister in dispose (passing the closure, per the bridge's
  mid-transition contract), and the index→key mapping becomes a **single
  shared resolver** (`_tabKeyFor(index)`) called from every
  `_selectedIndex` assignment: `_onItemTapped`'s switch (≈2068), `initState`
  (cold start lands directly on 15 via ≈766 and never calls `setActiveTab`
  today), and the fallback assignment at ≈2257 — otherwise Back on the very
  first Home sheet bypasses the handler (round-5 major). The root handler
  already yields when the bridge consumes (`main.dart:2712`). The handler returns true iff the sheet was
  open, after the atomic reset; the close button invokes the same reset
  function. The reset:
  switch `_mode` to catalog (`_clearQuery()` alone does not — that restore
  lives only in the Search-tab handler at ≈1476), clear the field and
  `_catalogQuery`, cancel any in-flight keyword search
  (`_kwSearchToken++`, `_kwSearching = _kwLoading = false` — otherwise a
  late result repopulates state Back just cleared), then
  `_searchSheetOpen = false`. The handler's true return is what consumes
  the press.
- **Focus latches the sheet** (review r3 #2): the existing search-field focus
  listener (≈1382) also sets `_searchSheetOpen = true` on focus gain — even
  while the shell branch is not yet eligible. An async style/hero arrival can
  then never unmount a focused blank field: by the time the branch activates,
  the latch is already set and the sheet layout renders.
- **Startup ordering** (review r3 #3): `_restoreKeywordState()` runs before
  `_loadHomeDefaultView()` (today the default-view load starts first, ≈1359),
  and a successful keyword restore suppresses the default-mode load entirely
  — otherwise a later-resolving catalog default flips the mode back and can
  fire a catalog search with the restored keyword text. This is a real
  pre-existing race made visible by the shell; fixing the ordering fixes it
  for classic too.
- When `_spotlightHero` is empty (CW/favourites-only content) the branch is
  inactive and the plain classic Column renders exactly as today.

## Step 3 — settings

- Off-TV style resolution (review r2 #4): a tiny pure helper
  `effectiveOffTvHomeStyle(raw) => raw == 'spotlight' ? 'spotlight' : 'classic'`
  used by `_spotlightSelected`, by the picker's selected-radio state, and by
  every Home Layout subtitle off-TV. A fresh install whose stored value is the
  TV default `'canvas'` (storage_service.dart:813) shows and selects Classic;
  the stored pref is **never rewritten** — a TV pairing to the same account
  keeps its Canvas.
- `tv_home_style_page.dart`: off-TV the picker lists Classic + Spotlight only;
  the auto-seed focus check (≈115) becomes `PlatformUtil.isTelevision`.
- `home_page_settings_page.dart`: the row gate (≈322) becomes
  `PlatformUtil.isTelevision`… and the row is *also* added off-TV — i.e. the
  row is unconditional; the `_firstTileFocusNode` handoff between Home Layout
  and Home Rows (≈336) is fixed so the node is used exactly once (Home Layout
  gets it; Home Rows' fallback keys off "did Home Layout take it", not off
  `isAndroidTvCached`).
- `settings_screen.dart` (≈1214): search-index nav entry loses `_isAndroidTv`.

## Step 4 — SpotlightBoard (`spotlight_board.dart`)

- `dpad` parameter; `_M` gains `tier` (constructor takes width + dpad).
- Radius moves into `_M` (wide stays 7 — byte-identical TV paint).
- Compact card: caption **below** the art. The row's tight-viewport trick is
  preserved by making the row viewport `posterH + captionBlock` on compact and
  the card a `Column[art SizedBox(posterH), caption]`; wide keeps today's
  structure exactly (review #4 — this is a layout change, not a metric).
- Compact hero (64% of board height): centered identity — logo slot centered,
  metadata line, CTA row (`▶ Open` pill → `onHeroOpen`, the same routing as
  TV's OK), tappable dots. No description line. The `leftThirdBusy` flip is
  wide-only.
- Touch hero drivers (`!dpad` any tier): 6 s auto-advance timer +
  horizontal-drag swipe. The timer pauses when a route covers the board
  (`ModalRoute.isCurrent` checked at fire time — cheaper and more reliable
  than route observers), when the search sheet is open (host passes
  visibility via the existing widget rebuild — timer only runs while the
  board is mounted and current), and under `WidgetsBindingObserver` paused
  state. **TV cadence untouched**: the existing 4 s advance-when-trailers-off
  behaviour (pinned by `spotlight_board_test.dart:172`) keeps running through
  the same code path it uses today.
- Hover (pointer): `_hover` state on `_Card`, separate from focus, rendering
  `focused || hovered` — pointer exit can't erase a DPAD focus visual.
- Long-press: already wired (`onOptions`); no claim of new menu work.
- `onDwell`/trailer contract: untouched (TV-only by the host's wiring).

## Step 5 — Showcase (`showcase_parts.dart`, `detail_layout_showcase.dart`)

- `ShowcaseMetrics` is computed **once** from the page's `LayoutBuilder`
  width (not `MediaQuery`) in `DetailShowcase._pageBody` and threaded down —
  including the two reads that resolve through the State's context today,
  `_peekFor` (≈221) and `_episodes` (≈526); `ShowcaseMetrics.of(context)`
  remains as a fallback for callers outside this layout. It absorbs the
  review's list of bypasses: `kShowcaseGutter` call sites (67, 370, 699), the
  source card (1147 — wide keeps bound cards at exactly 280×66 and the add
  card at 150, byte-identical), the scattered type sizes, and the episode
  rail height (531). Wide values are chosen to be numerically identical to
  today's output.
- Compact presentation (`tier == compact`, which already implies touch):
  - `ShowcaseEpisodeCardCompact` — still 16:9 at 62% width + integrated plate
    (eyebrow, title, 3-line synopsis, `▶ runtime`, kebab → `view.options(ep)`),
    tap → `view.play(ep)`, progress + watched marks preserved.
  - `ShowcaseSeasonPill` + anchored popup: positioned overlay at the pill,
    no scrim, rows call `view.selectSeason(n)`; dismiss on outside tap, back
    (`PopScope`), and selection; repositions to stay inside the viewport;
    max-height with internal scroll.
  - `ShowcaseIdentity` compact: centered stack, synopsis clamped to 2 lines
    with inline MORE. On compact the identity's content column is laid out in
    flow (the art is a positioned backdrop behind it), so expanding MORE
    grows the band instead of overflowing a fixed height. CTA row centered.
    Existing action wiring reused.
  - The band list matches the compact rendering (review r2 #3 — `dpad:false`
    still receives arrow keys from desktop keyboards and phones with external
    keyboards): on compact the seasons band carries **one node — the pill's**
    (Enter/OK opens the popup; the popup rows are focusable and Escape/Back
    closes it), and the episode band's nodes are mounted by the compact cards
    through the same `DetailEpisodeInteraction` wrapper the wide cells use.
    No band ever lists a node its rendering doesn't mount.
- Depth on touch (review #7): a **separate `_scrollDeep`** driven by the
  scroll offset (deep past 40% of viewport, shallow under 30% — hysteresis),
  never touching `_bandKey`. Effective depth = `dpad ? _deep : _scrollDeep`,
  and **all three visual consumers** (`ShowcaseAmbient`,
  `ShowcaseBackdropScrim`, `ShowcaseStickyLogo`) read the effective value,
  not `_deep`; every transition of the effective value fires `model.onDepth`,
  because the parent uses it to swap sharp/ambient backdrop and stop trailers
  (`merged_series_detail_screen.dart:326`, `1162`).
- Wide non-TV episode cells: kebab, hover-revealed with pointer, always
  visible on touch. TV rendering byte-identical.

## Step 6 — tests

- Existing suites stay green: `spotlight_board_test.dart` (wide surface),
  `detail_showcase_test.dart` (960×540), `spotlight_spec_test.dart`
  (untouched — pins the TV canvas).
- Metrics: geometry-level tests (rendered sizes at 390/834/1440 surfaces),
  since `_M` is private — assert poster width ≈ 0.243·w at 390 with
  `dpad: false`, 0.1354·w at 390 **and** at 834 with `dpad: true` (the
  dpad-is-always-wide rule, made unambiguous), 0.16·w at 834 with
  `dpad: false`, caption below art on compact only.
- Board behaviour: swipe advances hero; 6 s timer advances (`dpad: false`);
  timer absent under `dpad: true` beyond the existing 4 s cadence; dots tap;
  CTA routes through `onHeroOpen`; hover doesn't clobber focus visual.
- Showcase behaviour at 390×844 (`dpad: false`): integrated card present,
  kebab fires `options`, tap fires `play`; season pill opens popup, selects,
  dismisses on outside tap; scroll past threshold flips effective depth and
  fires `onDepth`; hysteresis holds; at 960×540 `dpad: true` nothing changes.
- Shell state machine — **implementation note**: SearchScreen proved
  un-pumpable in a widget test (its initState fans out to live plugin
  channels — SharedPreferences, IptvMediaStore, trackers — none of which the
  repo currently mocks; no existing test pumps it either). Per the stated
  fallback, the floor is: the latch/force logic implemented as three small
  derived getters + one reset function (`_sheetForced`, `_searchSheetOpen`,
  `_spotlightShellActive`, `_closeSearchSheet`) reviewed line-by-line, plus
  the board/detail widget suites. The transition matrix (open → search →
  clear → close; keyword default; restored keyword; Back at each state; the
  two async-arrival races) is covered by construction — forced conditions and
  the focus latch both pin the sheet open before any branch swap can unmount
  the field — and is called out for the on-device pass. THE GAP: no automated
  SearchScreen-level test; noted explicitly. SearchScreen-level widget coverage is
  attempted on top; if the screen proves un-pumpable (it hosts live
  services), the pure-helper matrix plus the board/detail widget tests are
  the floor, and the gap is noted explicitly.
- `flutter analyze` on touched files; full runs of the affected test files.

## Cut from scope (explicit follow-ups)

- Hero trailers anywhere off-TV (cut by review #8 — `_heroTrailerActive` is
  the TV shell lifecycle, not a render flag).
- "My List" on the hero CTA.
- Portrait key-art source for the detail hero.
- Other stage home layouts off-TV; favourites rails on Spotlight (pre-existing).
- Compact presentation on a narrow TV (deliberately excluded by the tier rule).
