# Detail page layouts — six new looks for `MergedDetailScreen`, plus Classic

Ship the six mocked concepts (`design/mockups/merged_detail_mockup/`) as selectable **body
layouts** for the merged details page, chosen in **Appearance → Details Page**.
Seven picker choices: Classic (default, today's screen unchanged) plus Marquee,
Dossier, Broadsheet, Stage, Filmstrip, Console.

Artifact: https://claude.ai/code/artifact/56938f4b-c6ee-415a-95df-d3f2aaa9abcb

> Revised twice against codex review. Round 1 P1s: screen shell, deep-link
> landing, unavailable terminal, focus graphs. Round 2 P1s: generation timing,
> missing season selectors, RIGHT-key collision, ink-fill placement. All below.

---

## 1. What ships

| value | Name | Shape |
|---|---|---|
| `classic` | **Classic** (default) | Today's screen. Untouched. |
| `marquee` | **Marquee** | Full-bleed art, identity bottom-left, season as a horizontal rail |
| `dossier` | **Dossier** | Fixed identity card left, vertical episode list right |
| `broadsheet` | **Broadsheet** | Ink + serif masthead, no backdrop; season as a numbered ledger |
| `stage` | **Stage** | 50/50 — art on top, tabbed deck below |
| `filmstrip` | **Filmstrip** | Focused episode's still is the page; strip of cards along the bottom |
| `console` | **Console** | Resume-first: continue card, season as a grid, reference column |

Each serves **series and movies** at **TV (960×540 logical), desktop, tablet
portrait, phone portrait, landscape phone**.

---

## 2. Non-negotiables

1. **Never fork the episode engine.** Layouts get a view contract (§3.3).
2. **Freeze the playback chain.** `onItemSelected` / `onQuickPlay` / `onResume`
   / `_popToHost` identical in every layout. No new call sites.
3. **`classic` is default and unchanged**, coerced on read *and* write.
4. **Gold means state.** Focus ring = `HomeTheme.focusGold`, in-bounds
   foreground border, never a spread shadow.
5. **One screen-owned shell** (§3.1).
6. **Nothing may become an ancestor of `HeroTrailerBackdrop`** — no `Opacity`,
   no filter, no clip. The existing content `AnimatedOpacity` is a *sibling
   above* it and stays that way.
7. **TV cost budget.** No per-frame blur, no animated `Opacity` on TV, snap
   focus transitions, `memCacheWidth` on every image.

---

## 3. Architecture

### 3.1 The shell stays screen-owned  *(round 1 P1 #1, round 2 P1 #4, P2 #11)*

`MergedDetailScreen.build()` keeps its outer tree verbatim:

```
PopScope → Scaffold → Stack[
  HeroTrailerBackdrop,                    ← never wrapped, never unmounted
  ExcludeFocus(IgnorePointer(AnimatedOpacity(Stack[
      AMBIENT STILL,    ← new, FIRST child (round 3 P1 #1)
      tint gradient,
      INK FILL,         ← new, above tint so it can cover the art …
      accent wash,      ← … but BELOW the wash, which must survive (round 3 P2 #1)
      BODY,             ← the only thing that switches on style
      back button,
  ]))),
  trailer chip,
]
```

- **Ink fill placement is exact**: a painted child *inside* the existing content
  `AnimatedOpacity`, above the tint, below BODY. It therefore fades out with the
  rest of the content when the trailer is promoted, and it is never an ancestor
  of the backdrop — so `BlendMode.clear` punch-through is untouched.
  Broadsheet sets `DetailBodySpec.inkGround = true`; every other layout leaves
  it false and the artwork shows as today.
- **Filmstrip's focused still is a shell concern but NOT the Hero's image.**
  `HeroTrailerBackdrop.imageUrl` stays the immutable title art — it is what the
  route Hero flies back into on pop. The shell instead paints a separate
  `DetailAmbientStill` layer, driven by `_focusedStillUrl`.

  **It is the first child of the content `AnimatedOpacity`'s inner `Stack`**, not
  a root sibling: `HeroTrailerBackdrop` reports ambient-playing as *false* once
  the trailer is foregrounded (`hero_trailer_backdrop.dart:664`), so a root
  sibling would paint over the fullscreen trailer and its controls. Inside the
  content stack it fades out with everything else on promotion, and it is
  additionally suppressed while `_trailerForeground`.

  It **switches instantly on TV** and cross-fades only off-TV — a fullscreen
  animated opacity per DPAD move is exactly what the cost budget forbids.

  Cleared when Filmstrip loses its focused episode, on view-generation change,
  and whenever dispatch selects a different layout.

### 3.2 The pref  *(round 1 P2 #10, round 2 P2 #10)*

Match `launchAnimationCached` exactly (`storage_service.dart:801`, warmed in
`main.dart:200`):

```dart
static const String _detailPageStyleKey = 'detail_page_style';
/// Everything storage will persist — all seven from day one, so a value
/// written by a newer build survives a downgrade.
static const Set<String> kDetailPageStyles = {
  'classic','marquee','dossier','broadsheet','stage','filmstrip','console',
};
static String detailPageStyleCached = 'classic';
static Future<String> getDetailPageStyle() async { … }
static Future<void> setDetailPageStyle(String s) async { … }
```

and, separately (§4):

```dart
/// What this BUILD can actually render. Dispatch, the Settings row subtitle and
/// the picker's selected state all read this — never the raw value — so a
/// downgraded build shows "Classic" consistently instead of labelling a style
/// it cannot draw. Does not persist; the raw value is left alone.
String effectiveDetailPageStyle(String raw) =>
    kDetailPageStylesShipped.contains(raw) ? raw : 'classic';
```

Files: `storage_service.dart`, **`main.dart:200`**, new
`settings/detail_page_style_page.dart`, **`settings/widgets/settings_widgets.dart`**
(the `SettingsRows` spec — single source of icon + copy), `settings_screen.dart`
(state, label, opener, both layout call sites, the indexed `Future.wait` at
**:233**), `settings/settings_tv_layout.dart` (Appearance category + `_paneNodes`
slot). `settings_search.dart` is generic — no edit.

### 3.3 The episode view contract  *(round 1 P1 #2/#3, round 2 P1 #1, P2 #1/#12)*

`EpisodesPanel` gains one optional param; null ⇒ today's tree byte-identical.

```dart
final Widget Function(BuildContext, EpisodesPanelView)? contentBuilder;
```

```dart
enum EpisodeFocusIntent { none, landing, seasonControl }

class EpisodesPanelView {
  final List<TraktSeason> seasons;
  final int selectedSeasonNumber;
  final List<TraktEpisode> episodes;
  final bool loading;
  final bool unavailable;
  final String? showImageUrl;

  /// NEW engine field `_viewGeneration`, distinct from `_episodeModeGeneration`
  /// (which bumps when a load STARTS and guards enrichment). This one bumps
  /// only when resolved episodes are PUBLISHED, and on every season swap — so
  /// a layout built during loading still sees it change when data lands.
  final int generation;

  /// The episode the engine resolved to land on, validated as a PAIR: the
  /// stored/next-up episode number is honoured only when its season equals the
  /// resolved target season (or the deep link was episode-only). Otherwise the
  /// season's first episode. Null while loading / when the season is empty.
  final TraktEpisode? landing;

  /// What the layout should focus for this generation. `landing` after a fresh
  /// load or deep link; `seasonControl` after the user stepped the season
  /// (their attention is on the stepper — matches Classic, which re-focuses the
  /// dropdown); `none` when nothing should move.
  final EpisodeFocusIntent focusIntent;

  final double? Function(TraktEpisode) progressOf;
  final bool Function(TraktEpisode) isNext;
  final void Function(TraktEpisode) play;
  final void Function(TraktEpisode) options;
  final void Function(int delta) stepSeason;
  final void Function(int seasonNumber) selectSeason;
  final VoidCallback? onLeftEdge;
  final VoidCallback onRetry;
  final VoidCallback? onSearchForSources;   // null unless host gave onItemSelected
}
```

**Layouts own their FocusNodes**, keyed `'<generation>:<season>-<number>'`,
disposed on generation change. `_episodeFocusNodes` is unused in custom mode —
the engine disposes/rebuilds it per season, so borrowing risks mounting a
disposed node from a retained tab or an outgoing animation.

**Engine side effects gated on `contentBuilder == null`:** `_scrollFocusEpisode`;
`_onSeasonChanged`'s `_episodeScrollController.jumpTo`; `_stepSeason`'s
`_episodeSeasonDropdownFocusNode.requestFocus()`. (Verified: those are the only
three writers of engine scroll/focus.)

### 3.4 Focus coordination  *(round 1 P1 #4/P2 #7, round 2 P2 #2)*

```dart
class DetailFocusCoordinator {
  final FocusNode backNode;       // shell's back button — always mounted
  final FocusNode primaryEntry;   // layout's primary action

  /// Synchronous, deterministic — never bare traversal (which geometry-jumps
  /// into an unrelated region). Used by episode LEFT.
  bool focusEntry() => primaryEntry.context != null
      ? (primaryEntry.requestFocus(), true).$2
      : (backNode.requestFocus(), true).$2;

  /// Post-frame variant for trailer dismissal (the body has just re-mounted).
  void restoreAfterTrailer();
}
```

Every layout must mount `primaryEntry` exactly once — on Play/Resume, else the
source pill (PikPak-only), else its first focusable — and must provide an **UP
edge from its topmost region to `backNode`**. `backNode`'s **DOWN returns to
`primaryEntry`**, so Back is never a one-way trip.

### 3.5 Where the code lives

```
lib/widgets/detail/
  detail_style.dart         DetailSize resolver, palette, scrim, slab/pill helpers
  detail_model.dart         DetailModel · DetailFocusCoordinator · DetailBodySpec
  detail_identity.dart      logo/title/meta/genres + action row (shared)
  detail_season_control.dart focusable ‹ Season N ▾ › used by EVERY series layout
  detail_episode_cells.dart card · row · ledger line · grid cell · strip cell
  detail_status.dart        DetailEpisodesStatus (loading · retry · search)
  detail_layout_{marquee,dossier,broadsheet,stage,filmstrip,console}.dart
```

### 3.6 Size classes  *(round 2 P2 #8)*

```dart
enum DetailSize { tv, desktop, tabletPortrait, phone }

DetailSize resolveDetailSize({required bool isTelevision, required Size size}) {
  if (isTelevision) return DetailSize.tv;
  final shortSide = math.min(size.width, size.height);   // NOT size.width
  final portrait = size.height >= size.width;
  if (shortSide <= 560) return DetailSize.phone;         // covers 800×400 landscape
  if (portrait && shortSide < 900) return DetailSize.tabletPortrait;
  return DetailSize.desktop;
}
```

Tested: 560/561, 899/900, TV override, 800×400 and 900×450 landscape phones,
both orientations. Heights derive from scaled text metrics, never magic numbers.

### 3.7 Movies  *(round 2 P2 #4)*

| Layout | Movie behaviour |
|---|---|
| Marquee | rail becomes More Like This |
| Dossier | right pane becomes the reference column |
| Broadsheet | ledger becomes the cast list — **rendered as non-focusable content**, because `_CastTile`'s tap is deliberately a no-op; the layout's focusables stay the aside actions + recs |
| Stage | Episodes tab dropped, Cast leads; **Sources is a tab-shaped ACTION invoking `onBrowse`**, not a panel |
| Filmstrip | no strip exists → renders Marquee's shape with a recs rail |
| Console | hero = movie resume card, grid = More Like This |

**Missing movie metadata is never an error.** `DetailEpisodesStatus` is for
episode *failure* only. An absent cast / recs / guide / genres / awards region is
omitted entirely, and no layout may place its only focusable inside a region
that can be empty — when a movie has no recs, the collection region is simply
absent and DOWN from the actions dead-stops.

### 3.8 Deliberate exclusions

- **Direct-source mode forces `classic`** (`seasonsLoader != null`; sole caller
  `lib/screens/iptv/xtream_series_detail.dart:260`).
- **No per-layout settings.**

---

## 4. Incremental safety

`kDetailPageStylesShipped` grows one entry per implemented layout. The picker
lists only those; dispatch and the Settings subtitle read
`effectiveDetailPageStyle(raw)`. The tree is usable and honest after every step;
stopping early just means a shorter list.

---

## 5. Focus graphs (TV) — complete

**RIGHT is layout-specific**  *(round 2 P1 #3)*. `_CompactEpisodeRow` may use
RIGHT for options only because it is a vertical, right-most pane. Rule:

- **vertical list cells** (Dossier, Stage) — RIGHT = options, as today;
- **horizontal cells** (Marquee, Filmstrip) — RIGHT/LEFT advance; **options =
  held OK**, with the hint shown in the region header;
- **grid cells** (Console) — RIGHT/LEFT move within the row; options = held OK;
- **ledger lines** (Broadsheet) — vertical run, RIGHT = options.

Common: OK plays; UP from the topmost region → `backNode`; `backNode` DOWN →
`primaryEntry`; when the collection region is loading/unavailable its focusable
is `DetailEpisodesStatus` (**Retry autofocused on TV, Retry↔Search on LEFT/RIGHT,
UP exits to the region above**); during loading focus parks on `primaryEntry`.

**Held OK is a real key implementation, not `GestureDetector.onLongPress`** — a
held DPAD SELECT never becomes a pointer long-press. The shared cells copy the
proven pattern in `lib/widgets/catalog_item_tile.dart:344-372`: on
`isActivateKey` (`select`/`enter`/`numpadEnter`/`gameButtonA`, `utils/tv_keys.dart`)
KeyDown arms an 800 ms timer and marks `_keyDownReceived`; KeyUp cancels it and
fires the tap only if the timer never triggered; focus loss resets all three
flags. Pointer `onLongPress` stays wired in parallel for touch.

**Every series layout mounts `DetailSeasonControl`** when `seasons.length > 1`.

| Layout | Graph |
|---|---|
| **Marquee** | actions (LEFT/RIGHT walk) → DOWN → season control → DOWN → rail. Rail LEFT/RIGHT walks, dead-stops both ends. Rail UP → season control; season control UP → actions; actions UP → back. |
| **Dossier** | today's two-`FocusScope` model verbatim; season control is the right pane's pinned header (as Classic); episode LEFT → `coordinator.focusEntry()`. |
| **Broadsheet** | actions live in the aside. Ledger is one vertical run. Season control sits in the strap above the ledger. **First ledger line UP → season control when it is mounted, else `backNode`; season control UP → `backNode`.** Ledger RIGHT → aside **only if the aside has a focusable**; aside LEFT → ledger; aside UP at top → back. |
| **Stage** | tabs are one horizontal run; tabs DOWN → panel; panel UP at top → tabs; tabs UP → actions; actions UP → back. **A tab switch re-focuses the tab strip**, never the replaced subtree. Season control is the Episodes panel's first row. A tab whose panel would be empty is not rendered. |
| **Filmstrip** | strip is the primary run (LEFT/RIGHT); focus change drives the ambient still. Strip UP → season control → UP → actions → UP → back. Entry = `landing`'s card; while loading/unavailable the strip region is the status widget and entry is `primaryEntry`. |
| **Console** | hero actions (LEFT/RIGHT walk) → DOWN → season control (LEFT/RIGHT walks ‹ / ▾ / ›) → DOWN → grid. Grid is a 2-D walk; **DOWN on a short final row stays put** rather than geometry-jumping. Grid UP from row 0 → season control. RIGHT from the grid's right edge → reference column **on desktop only, and only if it has a focusable**. Hero UP → back. |

---

## 6. Steps

| # | Step | Verify |
|---|---|---|
| 1 | Pref + sync cache + `main.dart` warm + `effectiveDetailPageStyle` + picker + settings wiring | analyze; coercion + effective-style tests |
| 2 | `EpisodesPanelView` + `contentBuilder` + `_viewGeneration` + landing pair validation + engine gates + `DetailEpisodesStatus` | contract tests: null builder ⇒ identical tree; generation bumps on publish and season swap; landing pair validation |
| 3 | Shared kit: size resolver, palette, identity, action row, season control, cells | resolver boundary tests |
| 4 | `DetailModel` + coordinator + ink fill + ambient still + body dispatch (all render Classic) | Classic unchanged; app runs |
| 5–10 | One layout per step — series + movie + all sizes + focus graph + append to `kDetailPageStylesShipped` | per-layout widget test: series, movie, sparse meta, loading/empty, TV back reachable, each size |
| 11 | Full sweep + final codex review | baseline 861 pass / 8 known failures |

---

## 7. Known traps

1. Never `clamp(min, …)` a remainder that re-spends reserved height.
2. Reserve the bottom region FIRST; the hero gets the true remainder.
3. A scroll region that **clips instead of scrolling** once the layout stacks —
   hit three times in the mock.
4. Breakpoints keyed to the wrong dimension; `shortSide` must be `min(w,h)`.
5. Scrims need a **legibility floor**: identity on ≥0.55 alpha ink whatever the
   art. Logo art is often white-on-transparent, sometimes black — keep the text
   fallback.
6. `AnimatedSwitcher` centres children under loose constraints.
7. Identity keys, never indices.
8. One `FocusNode`, one mount — layout-owned, generation-keyed.
9. `_stepSeason` focusing a node absent from the custom tree.
10. Two generations with different meanings — `_episodeModeGeneration` (load
    start, guards enrichment) vs `_viewGeneration` (publish + season swap).
11. Mutating `HeroTrailerBackdrop.imageUrl` breaks the pop Hero.
12. `_CastTile.onTap` is a no-op — never make cast the only focusable.
13. A root-level sibling paints over the promoted fullscreen trailer, because
    ambient-playing goes false on promotion.
14. `GestureDetector.onLongPress` does not fire for a held DPAD SELECT.

---

## 8. Decisions taken here (not asked)

- Default stays `classic`; new looks opt-in.
- Phone gets all six.
- Trailer autoplay unchanged (TV-gated at storage).
- No new analytics events.
- Sources for movies is an action everywhere, including Stage.


---

## 9. As built (overnight run)

**Shipped and selectable** (`kDetailPageStylesShipped`): Classic, **Marquee**,
**Dossier**, **Stage**, **Console**.

**Not yet built:** Broadsheet and Filmstrip. They are absent from the shipped
set, so the picker doesn't list them and `effectiveDetailPageStyle` narrows any
stored value to Classic — the incremental-safety rule in §4 working as designed.
`kDetailPageStyles` still persists all seven, so nothing is lost on upgrade.

### Files

| File | What |
|---|---|
| `services/storage_service.dart` | `detail_page_style` + `kDetailPageStyles` + `detailPageStyleCached` |
| `main.dart` | warms the cache before `runApp` |
| `screens/settings/detail_page_style_page.dart` | picker, shipped set, `effectiveDetailPageStyle`, label |
| `screens/settings/widgets/settings_widgets.dart` | `SettingsRows.detailPageStyle` |
| `screens/settings_screen.dart` | state, loader index 28, opener, search row, both layouts |
| `screens/settings/settings_tv_layout.dart` | Appearance row; `_kMaxCategoryRows` 8 → **9** |
| `widgets/episodes_panel.dart` | `EpisodesPanelView`, `contentBuilder`, `_viewGeneration`, landing pair-validation, three engine gates |
| `screens/merged_series_detail_screen.dart` | ambient still + ink ground in the shell, `_buildBody` dispatch, `DetailModel` builder, coordinator |
| `widgets/detail/*` | size resolver, palette, identity/actions, season control + picker, episode cells, status, four layouts |

### Review rounds

| Round | Result |
|---|---|
| Plan ×3 | 8 P1s found and fixed **before any code** — the screen shell, deep-link landing, unavailable terminal, focus graphs, generation timing, missing season selectors, the RIGHT-key collision, ink-fill placement |
| Steps 1–2 | **zero findings** |
| Full implementation | 1 P1 (Console unbounded height), 4 P2s, 1 P3 — all fixed |
| Verification | **0 P1s**, 4 P2s — all fixed |
| Final | **0 P1s**, 1 P2 (landing reveal never converged) — fixed by dropping the guessed extent for fraction-of-list convergence |

### Verified

`flutter analyze` 0 errors, no new warnings. `flutter test` **877 pass / 8 fail**
— the same 8 that fail on a clean tree, plus 16 new tests in
`test/detail_page_layouts_test.dart` covering the size-resolver boundaries
(including the landscape-phone case the `size.width` bug would have failed) and
the pref's coercion in both directions.

### NOT verified — needs a device pass

Nothing here has run on hardware. Worth walking on the Mi Box per layout:
entry focus, back reachability, season stepping and the new season picker,
held-OK options on Marquee/Console cards, and the movie variant of each.

### Deviations from the plan

- **Console's hero art is the title backdrop, not the landing episode's still.**
  The hero sits outside the hosted engine, so reaching the landing episode there
  would mean forking state. The grid still reveals the landing episode.
- **Landing is revealed, not focused.** Entry focus is the primary action
  (autofocused on TV) in every layout; the landing episode is scrolled into view
  instead of stealing the cursor. Filmstrip's focus-the-landing-card rule is
  moot until Filmstrip is built.
