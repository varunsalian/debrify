# Detail showcase parts refactor — plan

Written 2026-10-04 on `refactor/codebase` at `10ceef60`; the file is unchanged
since `f73f4800` (2026-09-17). Follow [AGENTS.md](../../AGENTS.md).
Revised 2026-10-04 after Codex design review round 1 (at `8a527a4e`).

Read first: `spotlight-board-plan.md` (closest template: widget library behind a
re-export facade), `merged-detail-plan.md` (typedef aliases, format-only step 0
proof, completion review notes), `playlist-content-plan.md`, and the Progress
sections of those three and the PikPak plan. This plan reuses their technique,
checker (`check_verbatim_moves.py` / `check_settings_moves.py`),
`suite_evidence.py`, gate procedure and Linux handoff, and states only what
differs.

**Execution.** Own git worktree on `refactor/detail-showcase`, cut from
`refactor/codebase`; Progress records the execution base SHA at step 0 and every
proof names it. Commit after every step; never push; gate commits contain
`gate`. Remote CI stays pending until Claude pushes, so every step runs the
local CI-equivalent commands. Evidence is written **only** under
`refactor-evidence/detail_showcase/`. **Every manifest run passes an isolated
`--parser-package`** (inside this worktree's ignored `.dart_tool/`), including
self-tests and other features' manifests (PikPak exit-253 lesson).

**Parallel-execution boundaries.** Other processes share this repository's
object store and run in sibling worktrees. Within this worktree,
`suite_evidence.py` snapshots (`git_tree_evidence`: `git stash create` +
`git write-tree` on this worktree's index) are **serialized**: never two
`suite_evidence.py run`s, or a run alongside a commit/`git add`, at once.
Manifest runs that share one `--parser-package` are serialized too; any run
that must overlap gets its **own parser-package and kernel directory** (the
format proof compiles its kernel next to the parser package). Full-suite gates
are coordinated with other heavy load (another worktree's full suite, Docker
goldens, builds); a timeout under contention is rerun, not recorded. Gate runs
are **full-suite**: since `8a527a4e` `suite_evidence.py` records runner flags
such as `--no-pub` under `flags`, apart from `paths`, so a full run's env has
empty `paths` and `compare` reports any baseline suite missing from it. Every
base and gate is recorded with a `suite_evidence.py` at or after `8a527a4e`,
and Progress shows each env's `paths` (empty) and `flags`.

## Goal

`lib/widgets/detail/showcase_parts.dart` is 3,394 lines: 20 import directives
(lines 1–21, line 4 blank), no `part`
files, 18 public top-level symbols, 40 private classes (11 stateless, 14
stateful + 15 States) and 11 private top-level functions/consts; no enums,
typedefs, extensions, mixins or statics. It is the parts library of the
Showcase detail style (grounds, identity, seasons, episodes, cast, sources,
recommendations, parents guide, universe, Did You Know, notes, details).

Split it **move-only** into a new feature, `lib/features/detail_showcase/`, and
turn the original path into a **pure re-export facade** (spotlight-board
pattern). Unchanged: the widget tree, runtime type names, keys, `const`
placement, constructors, defaults, focus and the three lifecycle methods.

**Callers stay unchanged:** production `detail_layout_showcase.dart:28`
(`DetailShowcase`, uses all 17 public widgets/types) and
`showcase_availability.dart:13` (`ShowcaseMetrics.of` only); tests
`detail_showcase_test`, `detail_showcase_compact_test`,
`showcase_availability_test`, `pinned_sources_controls_test`. `merged_detail`
reaches the parts only through `DetailShowcase`
(`merged_detail_body_layout.dart:15`) and never imports the new feature. No
`lib/features/` file and no other detail screen uses this file.

**Why a feature behind a facade.** Inside `lib/features/` the code gains the
architecture checker, CI format and the analyzer allowlist, none of which cover
`lib/widgets/detail` today. `lib/ui/core/` is rejected (no demonstrated reuse;
no bridge mechanism for the service-type imports). `merged_detail` is complete,
and the parts are rendered by a `lib/widgets/detail` layout, not by it.

**Not a playback seam.** No player, trailer engine, video surface, launcher,
timer or controller import exists; trailer and play are host callbacks
(Contract 2). The ambient trailer and launcher live in the merged-detail shell.

| Temporary exception | Exit |
| --- | --- |
| Type-only service imports via `PRESENTATION_BRIDGE_IMPORTS` `show` lists | Typed models in `lib/models/` or the feature's `models/` |
| `PlatformUtil.isTelevision` in `_Hover` (Contract 5) | A TV-capability adapter |
| Legacy English text (Found 12) | Localization migration |
| `_plateFill` `unused_element` allowlist entry | Separate removal of the dead helper (Found 1) |

No size exception is needed.

## Public surface (unchanged, importable from the facade)

The 18 names: `ShowcaseMetrics` (`.of`, `k`, 19 metric getters),
`ShowcaseMetricsScope`, `kShowcaseGutter`, and the widgets `ShowcaseAmbient`,
`ShowcaseBackdropScrim`, `ShowcaseStickyLogo`, `ShowcaseIdentity`,
`ShowcaseSeasons`, `ShowcaseEpisodeCell`, `ShowcaseEpisodeCardCompact`,
`ShowcaseCast`, `ShowcaseSources`, `ShowcaseRecs`, `ShowcaseGuide` (State
private), `ShowcaseUniverse`, `ShowcaseDidYouKnow`, `ShowcaseBandNote`,
`ShowcaseDetails`. Declarations, docs, `const` constructors, `super.key`, field
order and defaults stay byte-identical to the format commit.

The facade holds only `export '…' show …` directives naming exactly these 18
symbols, plus comments: no imports, declarations or aliases. A test pins the
exported namespace to exactly the 18 names. `kShowcaseGutter` is unused but
public (no diagnostic) and moves as-is (Found 2).

## What it contains (lines at `10ceef60`; after the format commit the manifest is authoritative)

| Orig | Fmt | Area |
| --- | --- | --- |
| 1–21 | 1–21 | 20 import directives (relative, sorted) |
| 23–141 | 23–142 | `ShowcaseMetrics`, `ShowcaseMetricsScope`, `kShowcaseGutter` |
| 143–273 | 143–274 | `_ink`, `_slotFill`, `_plateFill`, `_ambientBed`, `_t`, `_activate`, `_keepVisible`, `_Hover`/State |
| 275–455 | 275–456 | grounds: Ambient, BackdropScrim, StickyLogo |
| 457–732 | 457–739 | `ShowcaseIdentity` (+ `_identityColumnCompact`, `_identityColumn`) |
| 734–1083 | 740–1090 | readouts: `_LogoOrTitle`, `_ExpandableSynopsis`, `_Chip`, `_MetaLine`, `_TrackerMark`, `_RatingBox`, `_hasHonors`, `_HonorsLine`, `_TechLine` |
| 1085–1333 | 1091–1340 | actions: `_Primary`, `_Circle` (ctors `new`, `.mark`) with States |
| 1335–1546 | 1341–1567 | seasons: `ShowcaseSeasons`, `_SeasonDropdown`, `_SeasonPill` |
| 1548–1972 | 1568–1993 | episodes: two public cells, `_KebabButton`, `_Badge` |
| 1974–2384 | 1994–2416 | cast (`_CastTile`), sources (`_SourceCard`), recs (`_Poster`) |
| 2386–2852 | 2417–2884 | guide: `_plainOf`, `_spoilersOf`, `_severityLevel`, `_SeverityMark`, `ShowcaseGuide`/State, `_GuideCard` |
| 2854–3195 | 2885–3227 | universe (`_UniverseCard`), Did You Know (`_DykCard`, `_DykMoreCard`) |
| 3197–3394 | 3228–3425 | `_Band`; `ShowcaseBandNote`, `_RetryChip`, `ShowcaseDetails` |

**Resources.** No owned `FocusNode`, controller, `Ticker`, `Timer`, subscription
or `GlobalKey`. All focus nodes are borrowed from `DetailShowcase` (`_grow`,
layout 618); animations are implicit only. Lifecycle code exists only in
`_PrimaryState.initState`/`dispose` (1114–1126) and
`_ShowcaseGuideState.didUpdateWidget` (2492–2507).

## Contracts that must not change

Pinned by behaviour tests and/or source guards. Guards read whole bodies,
comments included, through `test/support/detail_showcase_source.dart`, a
**manifest-driven** reader frozen in (b) (Step 0 item 5): each declaration
is selected from the original or its created destination, with manifest
aliases reversed.

1. **Public surface** as above; each name declared in exactly one destination
   and re-exported once.
2. **Playback is callbacks only.** The Trailer `_Circle` mounts only when
   `m.hasTrailer`, with `onTap: m.onTrailer` (550–559); `_Primary` forwards
   `m.onPrimary`/`m.onPrimaryLongPress` (660–667, 717–724);
   `ShowcaseBackdropScrim.thinned` only selects one of four `const`
   gradients. A guard bans `media_kit`, `hero_trailer_backdrop`, trailer
   engines, `video_player_launcher` and `player_launch` imports from the
   feature and facade. Tests: trailer tap calls a recording `onTrailer`
   exactly once; OK calls `onPrimary`; held OK calls `onPrimaryLongPress`.
3. **`_PrimaryState` / `TvHoldOk`.** `initState` eagerly assigns the `late
   final _hold` (closures read `widget` live); `dispose` is `_hold.reset()`
   then `super.dispose()`; `Focus(autofocus: true)`; focus loss resets the
   hold, gain calls `onFocused`; key routing (`onLongPress == null ||
   !isActivateOrSpaceKey` → `_activate`, else `_hold.handle`); pointer
   long-press → `HapticFeedback.mediumImpact()`. Tests: held OK fires after
   600 ms and not before; unmount mid-hold fires nothing later; focus loss
   mid-hold cancels; no long-press callback → OK activates at once; the haptic
   is recorded on `SystemChannels.platform`.
4. **Guide `didUpdateWidget`.** Only on `!identical(old.guide, guide)`: re-seat
   `_sel` from live focus (`indexWhere(hasFocus)` then `.clamp`), reset
   `_spoilers`, `_open`, `_openSpoilers`. Tests: same object keeps selection and
   open state; new object with focus held on category 2 → `_sel == 2` and the
   rest reset; new object without focus → 0; `_GuideCard` follow-focus select.
5. **Hover, focus, visibility.** `_Hover` returns `builder(ctx, false)` when
   `PlatformUtil.isTelevision`, else a `MouseRegion`; `_CircleState`'s own
   `MouseRegion` is **not** TV-gated (Found 4, pinned as observed);
   `_keepVisible` scrolls only a horizontal nearest scrollable (0.5, 220 ms,
   `easeOutCubic`); `_activate` accepts KeyDown enter/select/space/gameButtonA;
   `_RetryChip` doesn't call `_keepVisible`. Tests (`debugSetAndroidTvCached` /
   `debugSetTvOS`, reset in teardown): no `MouseRegion` under `_Hover` on TV,
   one on desktop; hover and focus give the same visual; focusing a rail card
   moves the rail, not the page; identity circles never scroll the page.
6. **Borrowed resources only.** A guard rejects `FocusNode(`, controller,
   `Timer`, `KeepAlive` and `dispose()` of a borrowed node in the feature.
7. **Layout topology** (`detail_layout_showcase` is unchanged, so these must
   keep matching): action-circle mount conditions/order (497–588) vs
   `_actionCount`; `ShowcaseSources.itemCount = 2 + (onBrowseAll ? 1 : 0)`;
   season row `34 * m.k` and the 34-pt pill; DYK nodes `entries.length +
   (total > entries.length ? 1 : 0)`; guide nodes = categories; compact seasons
   uses `nodes.first`. Existing tests cover these; goldens pin the result.
8. **Metrics.** `k => (compact || !touch) ? 1.0 : wideTouchScale(w)`; `.of`
   reads the scope, else `MediaQuery` width minus horizontal padding;
   `updateShouldNotify` compares `w`/`compact`/`touch`.
9. **Rendering.** Element tree, keys, `const`, private runtime type names (the
   name-based `'_CastTile'` predicate in `merged_detail_metadata_test` is
   style-dependent; keeping names is the safe default); `memCacheWidth` 32
   (ambient), `420*k` (sticky logo), 520 (`_LogoOrTitle`); 550/400 ms fades;
   the 0.58 `_ambientBed` veil. Goldens pin these.
10. **Season dropdown.** `_open()` awaits `showMenu<int>` then calls
    `widget.view.selectSeason` with no `mounted` check (Found 5, preserved);
    the `SeasonActionRegion` wrapping is unchanged.

## Destination layout

All under `lib/features/detail_showcase/presentation/`, flat: no
`application/`, `data/` or bridge folder (no state, I/O or playback to
separate). Estimates are formatted lines with imports; each file is measured in
its creation commit and must be **≤ 500** (checker-enforced).

| File | Contents | ≈ |
| --- | --- | --- |
| `showcase_metrics.dart` | metrics, scope, `kShowcaseGutter` | 120 |
| `showcase_style.dart` | `_ink`, `_slotFill`, `_plateFill`, `_t`, `_activate`, `_keepVisible`, `_Hover`, `_Band`, aliases | 215 |
| `showcase_grounds.dart` | Ambient, BackdropScrim, StickyLogo, `_ambientBed` | 205 |
| `showcase_identity.dart` | `ShowcaseIdentity`, `_hasHonors` | 300 |
| `showcase_identity_readouts.dart` | readout widgets, `_TrackerMark`, `_RatingBox`, aliases | 380 |
| `showcase_identity_actions.dart` | `_Primary`, `_Circle`, aliases | 275 |
| `showcase_seasons.dart` | seasons band | 240 |
| `showcase_episodes.dart` | episode cell, compact card, `_KebabButton`, `_Badge` | 445 |
| `showcase_cast.dart` / `_sources.dart` / `_recs.dart` | one band each | 150 / 190 / 125 |
| `showcase_guide.dart` | guide helpers, `_SeverityMark`, guide, `_GuideCard` | 475–493 (largest) |
| `showcase_universe.dart` / `_did_you_know.dart` | one band each | 160 / 210 |
| `showcase_notes.dart` | `ShowcaseBandNote`, `_RetryChip`, `ShowcaseDetails` | 150 |

Measured with the probe: the complete guide file is 493 lines with long alias
names and 475 with short ones, so keeping the whole guide in one file is
feasible. If it nevertheless measures above 500 at creation, the fallback is
`showcase_guide_readouts.dart`, which owns `_GuideCard` (+State),
`_SeverityMark` and `_severityLevel` together: `_GuideCard` constructs
`_SeverityMark` (orig 2835), which `ShowcaseGuide` also uses (2581, 2726), so
the card can't move alone. That file adds **two** pinned widget aliases
(`_GuideCard`, `_SeverityMark`, each typedef + constructor const), the
conditional inventory becomes **17 cross-file privates**, and `_plainOf` /
`_spoilersOf` stay private in `showcase_guide.dart`; no exception. Progress
records which branch was taken.

**Privates (corrects the inventory's "8 + 9").** `_ambientBed` is used only by
grounds (293) and `_hasHonors` only by `ShowcaseIdentity` (640, 696), so both
move privately with their sole consumer. `_TrackerMark`, `_RatingBox`,
`_KebabButton`, `_Badge`, the guide helpers and each band's own card stay
private in their band file (`_SeverityMark` stays with both its users, the
guide and `_GuideCard`). That leaves **15 cross-file privates** (17 under the
guide fallback above): 7 style
items (`_ink`, `_t`, `_activate`, `_keepVisible`, `_slotFill`, `_Hover`,
`_Band`) and 8 identity widgets (`_LogoOrTitle`, `_ExpandableSynopsis`,
`_Chip`, `_MetaLine`, `_HonorsLine`, `_TechLine`, `_Primary`, `_Circle`).

**Aliases, never renames (merged-detail precedent).** Each shared declaration
stays byte-identical and private in its owner (runtime type, keyless private
constructor and `const` unchanged); the owner adds pinned public aliases right
after it:
- 10 widgets (12 under the guide fallback): `typedef ShowcaseX = _X;` plus
  `const showcaseXConstructor = _X.new;` (`_Circle` also
  `showcaseCircleMarkConstructor = _Circle.mark`).
  Cross-library typedef calls otherwise report the private constructor's
  optional parameters unused.
- 5 functions/consts: `const showcaseInk = _ink;` and tear-off consts for
  `_t`, `_activate`, `_keepVisible`, `_slotFill`.

Owner-file uses keep the private name; other files use the alias; the manifest
registers each mapping and the checker reverses it and rejects a changed
target. The existing reversal (`type_aliases` in `check_settings_moves.py`)
maps a typedef name **globally**, so it cannot tell an owner-file alias use
from a cross-file one. This plan therefore adds an **opt-in, file-aware
alias-use validator** (a new config key, absent from every other manifest's
config) covering widget, function and const aliases: in the owner file each
alias appears only in its own declaration and uses keep the private name; in
every other file only the alias appears. The validator and the reversal
operate on **code identifiers and interpolation expressions only**: comment
and string-literal contents are preserved byte-for-byte (immutable comments
still name `_t` in metrics, `_ink` in grounds and `_SeverityMark` in
episodes). Fixtures with an active alias prove that an unchanged private
name inside a comment passes and that an alias substituted into that
comment fails. Declarations are pinned
**separately** and token-exactly: each typedef by `check_type_aliases`, and
**every constructor target** (`showcaseXConstructor = _X.new`, and
`showcaseCircleMarkConstructor = _Circle.mark`) and each function/const
tear-off (`showcaseInk = _ink`, …) by the new key. Every integrated manifest's
self-tests and runs stay passing unchanged. **Final alias names are fixed at
step 0** by a rename-plus-format probe, preferring names that cause no reflow (`_t` has ~70 call sites; the
merged `seriesDone` precedent). Any reflow-added optional comma is inventoried
by AST node and owner, and any new brace info by identity, or a shorter name is
chosen. No alias is exported by the facade.

**`_plateFill`** stays private and unused in `showcase_style.dart`. Its
`unused_element` warning goes into `dev/tool/analyzer_allowlist.txt` **in the
commit that creates the file** (PikPak `_email` precedent), at the destination
path, as the **full observed Flutter message**, with no final period:

```text
warning | unused_element | lib/features/detail_showcase/presentation/showcase_style.dart | The declaration '_plateFill' isn't referenced. Try removing the declaration of '_plateFill'
```

with a dated `# detail_showcase:` comment. `check_analyzer_allowlist.py`
matches (severity, rule, path, message) exactly and fails on stale entries,
so the entry is verified against the **complete scoped analyzer output** (all
CI analyze paths, as in `checks.yml`), not a single-file run, and the captured
line is compared with the entry before committing. No warning disappears or is
added.

**Service imports are type/cache-manager only** (no calls into service logic),
so each destination imports with an exact `show` list registered per file in
`PRESENTATION_BRIDGE_IMPORTS`: `debrify_image_cache` → `DebrifyImageCache`
(`.manager` passed to `CachedNetworkImage`); `imdb_enrichment_service` →
`CastMember` / `UniverseTitle` / `DidYouKnowEntry` (each file its own);
`imdb_parents_guide_service` → `ParentsGuideResult`, `ParentsGuideCategory`,
`ParentsGuideItem`; `trakt/trakt_episode_model` → `TraktEpisode`;
`series_source_service` → `SeriesSource` (URI kept; it re-exports
`lib/models/series_source.dart`). New files write sorted `package:debrify/…`
imports of only what they use; any `unused_import`/`unnecessary_import` is a
new diagnostic and fails.

**Guard rules** (step 1, `check_search_architecture.py`): `detail_showcase` in
`FEATURES`; `DETAIL_SHOWCASE_FACADE = "lib/widgets/detail/showcase_parts.dart"`,
`DETAIL_SHOWCASE_COMPLETE = False`; no facade back-import; no `lib/services/`
import except the registered `show` entries (no `LEGACY_PLAYBACK_BRIDGES`
entry); playback-import and resource bans (Contracts 2, 6); 500-line cap on
every feature file, no exceptions; no imports either way between
`detail_showcase` and `merged_detail` or `catalog_detail` (planned in parallel,
absent at `10ceef60`; the rule is by feature name) except `<other>/models/`.

At step 5 (`DETAIL_SHOWCASE_COMPLETE = True`): `main()` adds the facade;
`COMPOSITION_ROOTS` entry with comment; pure-export rule (only `export`
directives and comments, exactly the 18 names in `show`); the measured cap
(target ≤ 60, at most 80); `TEMP(detail_showcase)` rejected everywhere. Tests
run the real `main()` on a temporary tree copy and must reject: missing facade;
a facade declaration or import; facade over cap; an extra exported name; a
back-import; a `merged_detail` import; an unshown service import; a `TEMP`
marker. The unmodified tree passes.

## Technique

As in the merged-detail and spotlight plans, plus:

1. **Two step 0 originals.**
   - **(a) Format-only commit** (`style(showcase): format the original
     showcase parts`) is R, the approved application reference: manifest
     `--baseline`, relocation comparison and hash rule. `dart format` makes 12
     `diff -U0` hunks, 3,394 → 3,425 lines, idempotent. Tokens differ only by
     **6 AST-identified optional trailing commas** (Explore circle ×2
     contexts, SeasonDropdown, SeasonPill, `ShowcaseCast` constructor, cast
     tile constructor call). `merged_detail_format_proof.py` is **not**
     reused as-is: it hardcodes merged's source path, its mutation strings
     (`'Merged series page (experimental'`, `0xFF0B0B0E`) and 25 commas, and
     its `str.replace` mutations would silently no-op on this file. Add
     `dev/tool/detail_showcase_format_proof.py`, a showcase wrapper over the
     existing AST adapter (`merged_detail_format_proof.dart.txt`), or
     parameterize the merged script (`--source`, `--expected-commas`,
     mutation targets) with merged's current values as defaults so its own
     run is unchanged. Inputs: `--original`, `--formatted`, isolated
     `--parser-package`, a per-run kernel path, `--output`. It lists each
     comma by node and owner, **expects exactly 6**, and asserts that every
     mutation actually changes its input (`mutated != formatted`) before
     requiring that edited-comment (a showcase doc comment), trailing-comment,
     edited-literal (a showcase literal, e.g. `0xFF4A4A55`) and
     non-optional-comma negatives reject. **0 format-induced
     diagnostics** are expected (no wrapped `if`); any observed is recorded by
     identity in `base-fmt`, never fixed. The commit also **raises
     `dev/tool/file_size_baseline.txt:23` by hand** 3394 → 3425; it is lowered
     at each later step and removed once the facade is under 800.
   - **(b) Characterization checkpoint** (`test(detail-showcase): step 0
     original-code characterization checkpoint`): application files
     unchanged from R; adds the frozen tests, harness, source reader, checker
     config and macOS goldens. Progress records both hashes and proves
     `git rev-parse <b>:lib` = `<R>:lib`, likewise `pubspec.yaml` and
     `pubspec.lock`. No seam is expected (the parts take fixtures directly);
     if one proves necessary, the spotlight seam-checkpoint rule applies and R
     moves to it everywhere.
2. **Strict-lint baseline by identity.** Analyze R under
   `lib/features/analysis_options.yaml` in a detached worktree in ignored
   `.dart_tool/`, qualifying import URIs only. Expected: 1 warning
   (`_plateFill`), 4 `prefer_const_constructors` infos (`_Badge(label: 'UP
   NEXT')`, fmt 1648, 1651, 1821, 1824), and 2 `directives_ordering`
   infos at import lines 5 and 21 that come from the import-URI qualification
   itself (round-2 probe). They are recorded by identity as
   qualification-induced (not formatter-induced) and must disappear once the
   destination imports are sorted. A throwaway
   **alias probe** applies exactly the manifest's split, aliases and imports
   and must report 0 `use_key_in_widget_constructors`, 0
   `library_private_types_in_public_api` and no unused/unnecessary import;
   anything it does report is inventoried by rule, symbol and message.
   Combine baseline and probe by maximum, never sum. No `Key? key`,
   constructor, `const` or suppression changes; the 4 const infos stay.
3. **Whole declarations move verbatim** with docs and State. **The verbatim
   checker compares comments: never reword one**, including cross-file
   references that now name another file's private (`[_keepVisible]` 238,
   `_reveal` 211, `_SeverityMark rule` 1690,
   `EpisodesPanel._enrichEpisodeRatings` 1692, `_Poster` 2203,
   `[DetailShowcase]` 33/121, the stale "eight call sites" 148). The only
   edits inside moved bodies are alias substitutions at cross-file use sites;
   nothing is hoisted, reordered, wrapped, keyed or `Builder`-ed.
4. **Intermediate original.** Until step 4 the original keeps the unmoved code,
   imports the feature files it needs (aliases included) and `export … show`s
   each moved public name, so importers compile at every checkpoint. It never
   declares a forwarder.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline; (a) and `base-fmt`; deps report, manifest, config; lint/alias probes; harness, characterization, macOS goldens, (b); CI list; inventory; Linux script; step 0b review | Nothing moves |
| L | Linux originals in a separate commit (Claude captures; execution verifies and commits). **Blocking before step 2.** | — |
| 1 | Guard registration; metrics; style (aliases, `_Hover`, `_Band`, `_plateFill` + allowlist); shape/theme registration begins | 1, 5, 8 |
| 2 | Grounds; identity; readouts; actions | 2, 3, 7, 9 |
| 3 | Seasons, episodes, cast, sources, recs. **Full-suite gate 1.** | 5, 7, 10 |
| 4 | Guide, universe, Did You Know, notes/details; the original becomes the pure facade | 4, 5, 7 |
| 5 | `DETAIL_SHOWCASE_COMPLETE`, facade rules/cap, `checks.yml`, CI. **Full-suite gate 2.** | All |

### Step 0

1. **Baselines.** `detail_showcase/base` (`suite_evidence.py run` + whole-repo
   analyzer) on the untouched head with tree/SDK provenance (Flutter 3.44.8 /
   Dart 3.12.2; `--no-pub` recorded under `flags`, `paths` empty);
   `detail_showcase/base-fmt` after (a), equal by identity. At `10ceef60` the
   five related files gave 69 passes / 0 failures and the merged `showcase` golden passes on macOS.
2. **Dependency report** (`docs/refactoring/detail-showcase-deps.md`): per leaf
   (declaration, private top-level item, comment fragment) its destination,
   each cross-file private reference and alias, each service type and `show`
   entry, State reads of `widget`/`context`/`mounted`, and a wiring-checklist
   entry; reviewed before anything is pinned.
3. **Checker.** `dev/tool/detail_showcase_manifest.tsv` (LF only) and
   `detail_showcase_checker_config.json` with real-config fixtures;
   `--relocate lib/widgets/detail/showcase_parts.dart=lib/features/detail_showcase/`.
   Typedef/constructor tear-off pins reuse the merged-detail support; function
   and const tear-off aliases get an **opt-in** config key only if not already
   covered, with every integrated manifest's self-tests unchanged. Negatives:
   changed alias target; alias used in its owner file; renamed private class;
   reworded comment; new `const` or key; reordered `dispose`; lazy `_hold`;
   dropped `identical` in `didUpdateWidget`; `onTap: m.onTrailer` wrapped in a
   closure; `_Hover` TV gate removed; `_keepVisible` axis check removed.
   **Emitted-alias checks are staged:** `check_type_aliases` requires the
   destination typedef to exist, so a `type_aliases` (or validator) entry
   registered before its owner file exists fails. The alias table is fixed
   at step 0 in the deps report and Progress, but each alias's config entries
   enter in the step that creates its owner file; step 0 proves that a
   registration ahead of its owner is rejected (so staging is required, not
   tolerated).
4. **Harness** (`test/support/detail_showcase_fixture.dart`), with the model
   and host builders of `detail_showcase_test` copied in (not imported from a
   test): `AppThemeScope` with a named look; pinned `tester.view` size, DPR
   1.0, `en-US`, text scale 1.0; host-owned focus nodes disposed in teardown;
   recording `onTrailer`, `onPrimary`, `onPrimaryLongPress`, `onOpen`, `onTap`,
   `onAction`; platform flags reset in teardown; null artwork (deterministic
   placeholders, the spotlight decision); bounded pumps, no `pumpAndSettle`
   across the 600 ms hold; braces in tests; January UTC dates. Prove it on R
   first.
5. **Characterization tests** under
   `test/features/detail_showcase/presentation/`, frozen in (b), each passing
   in a detached worktree of (b) before any move:
   `showcase_primary_hold_test` (Contracts 2–3), `showcase_guide_update_test`
   (4), `showcase_hover_focus_test` (5), `showcase_band_contracts_test` (7, 8,
   10, `ShowcaseDetails`, `ShowcaseBandNote`/`_RetryChip` activation, sticky
   logo and thinned scrim visibility), `detail_showcase_surface_test` (facade
   namespace = 18 names) and `detail_showcase_source_contract_test`. The
   guards must pass **on (b) itself**, which precedes feature creation, and
   unchanged at every later checkpoint. The frozen reader
   (`test/support/detail_showcase_source.dart`) is **manifest-driven**: for
   each registered declaration it reads the original
   (`showcase_parts.dart`) or the destination file the manifest names, if
   that file has been created, and **fails when neither (or both) holds the
   declaration**, so a lost or duplicated declaration never passes silently.
   Final-topology requirements (every destination exists, the original is a
   pure 18-name facade, no declaration remains in it) are **dormant until
   completion**: they activate only when `DETAIL_SHOWCASE_COMPLETE = True` in
   `check_search_architecture.py` (absent counts as false, as at (b)). The
   step 0b review proves the guards pass on (b), fail on a declaration
   deleted from the original, and that the final-topology checks fire on a
   temporary copy of (b) with the flag set.
6. **Goldens.** The merged `showcase` golden (1200×900, wide touch, movie)
   stays. New deterministic scenes from (b), `detail_showcase_goldens_test.dart`
   → `test/goldens/detail_showcase/{macos,linux}/`: `tv_movie` (1920×1080,
   dpad, k = 1, identity focused); `compact_series` (390×844, seasons pill,
   compact episode cards); `wide_series_bands` (seasons, episodes, cast,
   sources, recs, wide guide plate, universe, DYK with "+N", band note and
   details); `compact_guide` (accordion, one row open). A taller
   `DetailShowcase` page can't produce the all-bands scene: `_heroHeight`
   is `viewport - peek` (layout 749), so the hero grows with the viewport
   and pushes the bands down. So `wide_series_bands` uses a **direct
   public-parts harness**: the public band widgets in a fixed-size column
   under an explicit `ShowcaseMetricsScope` (1280 wide, fixed `w`,
   `compact: false`, `touch` pinned) — no `DetailShowcase`, no hero.
   `compact_series` uses either the same parts harness or the full page at
   an **explicit, recorded scroll offset** (`jumpTo`, then a bounded pump).
   Every golden asserts that **each promised band's rect intersects the
   capture bounds** (`tester.getRect(...).overlaps(...)`) before matching, so
   a band laid out off-screen fails instead of silently passing. Motion
   timing is pinned (fixed pump durations past the 550/400 ms fades and the
   220 ms `_keepVisible` scroll; no `pumpAndSettle`); any look that focuses a
   `ParallaxFocus` card calls `ParallaxTravel.resetForTest()` in setUp and
   teardown. No trailer. Execution captures macOS into (b).
   **Claude captures Linux** from (b) in the calibrated
   `debrify-flutter:3.44.8` linux/amd64 Docker image (Colima): clone the branch
   into a mounted `$HOME` path, check out (b), verify `HEAD` and hashes, run the
   script, copy PNGs and evidence into the worktree. Execution verifies hashes
   and provenance and commits them as step L; Linux is strict from L on (the
   merged precedent).
7. **CI list.** Add to `dev/tool/ci_behavior_tests.txt` the three missing
   direct-importer tests (`detail_showcase_compact_test`,
   `showcase_availability_test`, `pinned_sources_controls_test`;
   `detail_showcase_test`, `metadata_source_management_baseline_test` and
   `merged_detail_views_test` are already listed), every new test and the
   golden test. Add known failures only as observed in `base`, by identity,
   under `# 2026-10-04 detail_showcase step 0:`; none are expected.
8. **Source-text inventory.**
   - **Shape:** 18 bare literal radii, 0 `app.shape.` calls (orig 1034, 1415,
     1454, 1605, 1610, 1683, 1768, 1782, 1842, 2360, 2362, 2438, 2571, 2616,
     2657, 2714, 2944, 2946); formatting keeps 18. Register each destination
     in `kExtractedShapeResidue` (never `kShapeResidue`) **in the commit
     that creates it**, zero-count files included, and the facade from step
     1 (the manifest test rejects nonexistent registered files). Because the
     residue check is an upper bound, every checkpoint also measures and
     asserts the slice total of exactly 18 and the facade ends at 0. The 488 token floor is
     unaffected.
   - **Theme:** `theme_surface_manifest.txt:11` (`details_themed`) gains an
     explicit `lib/features/detail_showcase/presentation/*.dart` pattern (no
     globstar); `lib/widgets/detail/*.dart` still covers the facade. Measure
     before and after: unchanged.
   - **Light ink:** not added to `PRIMARY` (`lib/widgets/detail` isn't
     primary), so classification is unchanged; record the measurement.
   - **Verify unaffected:** `detail_theme_test` (themed list excludes this
     file), `theme/source_guard_test`, `profile_source_guard_test`,
     `stale_runtime_guard_test`, `storage_member_map.tsv`. Historical design
     docs naming the path stay as they are.
9. **Linux capture script** (`dev/tool/capture_detail_showcase_linux_goldens.sh`,
   modelled on the merged-detail script): `set -euo pipefail`; resolves (b)
   and R by **exact subject**, piping all of `git log --format='%H %s'` into an
   awk that prints every match — **no `{ print; exit }`** (the early exit
   SIGPIPEs `git log`, which fails under pipefail) — and requires exactly one
   match; requires (b)'s `lib`/`pubspec.yaml`/`pubspec.lock` hash-equal R's;
   uses only (b)'s tests; checks Flutter 3.44.8 on Linux; captures once,
   verifies strictly, writes hash and revision evidence.

**Step 0b review** (on (b), before any move). Each ORIGINAL-only mutation must
be rejected by a real assertion failure, not a compile error: lazy `_hold`;
reordered `dispose`; `onPrimaryLongPress` routed to `onPrimary`; trailer tap
double-firing; `identical` removed from `didUpdateWidget`; `_sel` not
re-seated; `_Hover` ungated on TV; `_keepVisible` without the axis check;
`itemCount` without the browse term; `k` always 1.0; a golden-visible radius
change. Record `base3` at (b): only added, passing identities.

### Per step and gates

The playlist procedure with `--baseline <R>`. Every step runs: every integrated
manifest plus this one, with self-tests and an isolated `--parser-package`; the
per-symbol relocation comparison (zero additions); architecture and sizes
(lowering the line-23 ratchet); shape (18) and theme; CI format and scoped
analyzer with `check_analyzer_allowlist.py`; the strict comparison by identity
(the 1 warning and 4 const infos traced to original symbols); LF manifests and
staged diff; the focused characterization set plus the five existing related
files. No golden is ever regenerated against moved code. Gates run on
committed trees with no untracked inputs against the latest `detail_showcase/`
base; gate 2 also compares with gate 1. Gates are full-suite runs under the
parallel-execution boundaries above. Never `--record` a regression.

**Linux replays.** At completion (gate 2's commit) and again after
integration, Claude replays all four new goldens **and** the existing merged
`showcase` golden in the calibrated `debrify-flutter:3.44.8` linux/amd64
Docker image, as for step L: the replay checks out the committed revision,
records its input provenance (commit SHA, `lib`/`test`/`pubspec.yaml`/
`pubspec.lock` tree hashes, image ID, Flutter version) and verifies in
strict mode with **no regeneration**; Progress records each PNG's hash as
unchanged from step L (the merged golden from its committed hash).

**Step 5** also adds the facade to the `checks.yml` format (45) and analyze
(52) lists and `test/support/detail_showcase_*.dart` to the format list —
**paths before `| tee analyze.txt`, never after** — and records the facade's
`wc -l` breakdown (export directives + comments = total) and the final
per-file sizes.

### Integration (Claude)

Claude merges the branch and integrates shared files **semantically, by
union**: `check_search_architecture.py` (including `FEATURES`, which spotlight
also extends), `check_settings_moves.py` and any shared reader helper (opt-in
keys only), `shape_manifest_test.dart`, `theme_surface_manifest.txt`,
`ci_behavior_tests.txt`, `ci_behavior_known_failures.txt`,
`analyzer_allowlist.txt`, `checks.yml`, `file_size_baseline.txt`. Union and
dedupe registrations, `PRESENTATION_BRIDGE_IMPORTS` entries, CI paths,
known-failure identities, theme patterns, shape entries, `main()` facade paths
and `COMPOSITION_ROOTS`; keep every `*_COMPLETE`; take the lowest verified size
ceiling; keep every `checks.yml` path before `| tee`. Then, on the merged
committed tree: every manifest with self-tests; architecture, size, shape,
theme; CI format, analyze and allowlist; a full-suite comparison against each
branch's bases; and the Linux golden replay (Per step and gates) on the
integrated revision.

## Definition of done

1. **Facade:** pure re-export of exactly the 18 names, formatted, within its
   measured cap; both production importers, the four test importers and
   `merged_detail` compile unchanged.
2. **Feature:** every destination ≤ 500 lines, no size exception; the 15
   cross-file privates (17 under the guide fallback) cross only through
   pinned aliases, with owner-local spelling enforced by the alias-use
   validator; all other privates file-local; no runtime type name changes.
3. **Guard:** feature, facade rules and cap, `show`-list service imports, and
   the playback, resource, back-import and `merged_detail`/`catalog_detail`
   bans, each proven through the real checker.
4. **Tests:** all manifests with self-tests pass; every characterization test
   and guard from (b) passes unchanged; macOS and Linux goldens (four new plus
   the merged `showcase`) match the originals, with the completion Linux
   replay's provenance and unchanged PNG hashes recorded.
5. **Diagnostics:** no new diagnostics or suppressions; `_plateFill`'s warning
   only via its destination allowlist entry (full observed message, checked
   against the complete scoped output); the 4 const infos trace to their
   original members.
6. **CI:** behaviour list holds the direct-importer and new tests; shape slice
   totals 18 with 0 in the facade; theme surface unchanged; size baseline
   entry removed.
7. **Progress** records commits ((a) = R, (b), L, each step), the alias table,
   and as **pending device verification**: Android TV D-pad through every band,
   hold-OK on Play, the season `showMenu` popup on TV, Apple TV trackpad hover
   on circles vs cards, the trailer/play handoff through the merged shell; and
   remote CI.
8. **Gate 2** passes against the latest base and gate 1. Then stop and report.

## Explicitly not in scope

`DetailShowcase` (`detail_layout_showcase.dart`, 1,522 lines; a possible later
`detail_layouts` plan), `showcase_availability.dart`, `DetailModel`,
`EpisodesPanel`, `SeasonActionRegion`, `TvHoldOk`, `ParallaxFocus`, the
merged-detail shell and its trailer, services, Riverpod, localization, a
TV-capability adapter, accessibility semantics, and every bug fix or behaviour
change below.

## Progress

- Execution base: `14d173a9` on `refactor/detail-showcase`, dedicated
  `/Users/varunbsalian/Documents/Projects/debrify-wt/detail-showcase`. Only this
  worktree and owned nested proof worktrees are used; no branch switch or push.
  `flutter pub get` ran first; `pubspec.yaml` and lockfile unchanged.
- Step 0(a): format-only original, exact subject `style(showcase): format the
  original showcase parts`. Retain the oversized original temporarily until
  steps 1–4 move all 69 declarations and the shared band chrome. Ratchet
  3394 → 3425 is the formatter-only raise; later checkpoints only lower it.
- `detail_showcase/base`: full suite on untouched `14d173a9`, Flutter 3.44.8 /
  Dart 3.12.2, paths `[]`, flags `["--no-pub"]`: 11,093 success, 13 failure,
  28 error, 20 skipped. Stable tree; no untracked inputs. Whole analyzer
  recorded as `base-analyze.txt`; historical failure lists are not changed.
- `format-proof.json`: whole-file scanner tokens, comments and literals equal
  after removing exactly six AST-identified optional commas (Explore circle
  nested calls, SeasonDropdown, SeasonPill, ShowcaseCast constructor, cast tile
  call). All four negatives reject and each mutation changes its input.
  Parser and kernel live only under this worktree's `.dart_tool/`.
- Conservative choices: no application seam, deterministic null artwork,
  equal-length cross-file alias names to avoid body reflow; all moved comments
  remain verbatim. Linux originals will be separately verified/committed at L;
  absent originals block before builder moves. Original characterization/mutation
  replays and all-manifest replays are complete; see step 0b below. Extraction
  remains blocked at L.

### Step 0(b) — frozen original characterization checkpoint

- R / step 0(a) is `1165b624`. `base-fmt` is a full-suite run with paths `[]`
  and flags `["--no-pub"]`: 11,093 success, 13 failure, 28 error, 20 skips;
  every identity/outcome equals `base`. No new/fixed/missing/skipped identity.
- First concurrent `base-fmt-analyze.txt` transiently exposed nine additional
  unchanged-file diagnostics (generated assets, vendor lint options, existing
  dock metrics tests). Sequential original/reference replays establish zero
  format-induced additions. `base-fmt-analyze-replay.txt` and
  `step0-whole-analyze-final.txt` exactly equal `base-analyze.txt` (1,666
  diagnostic occurrences); preserve all attempted logs in the own namespace.
- `strict-original.txt` / `strict-baseline-identities.json`: original under
  feature rules, qualified imports only, one `_plateFill` warning, four
  `_Badge` const infos, and two qualification-induced `directives_ordering`
  infos at 5/21. `alias-probe.txt` has only the warning and four const infos;
  no unused/unnecessary import, key or private-public API diagnostic. Compare
  by maximum, never sum. No suppression or constructor changes.
- `detail-showcase-deps.md`, LF manifest and real-config fixtures pin all 69
  whole declarations, comment-fragment owners, State reads and per-entry wiring.
  Fixed aliases: `_ink→sInk`, `_t→st`, `_activate→sActivate`,
  `_keepVisible→sKeepVisible`, `_slotFill→sSlotFill`, `_Hover→SHover`,
  `_Band→SBand`, `_LogoOrTitle→SLogoOrTitle`,
  `_ExpandableSynopsis→SExpandableSynopsis`, `_Chip→SChip`,
  `_MetaLine→SMetaLine`, `_HonorsLine→SHonorsLine`, `_TechLine→STechLine`,
  `_Primary→SPrimary`, `_Circle→SCircle`. Typedef and file-aware alias entries
  remain empty in the production config until their owner creation; the full
  virtual split accepts all pins and rejects registration ahead of the owner.
  Constructor consts use `showcase<Name>Constructor`, plus
  `showcaseCircleMarkConstructor`; functions/consts use exact tear-off pins.
- The feature-aware normalization is opt-in; code/interpolation identifiers
  reverse aliases while comments/literal contents remain intact. Owner-local
  alias use, changed targets (including `.mark`), class rename, changed comment,
  added const/key, lifecycle/hold/guide, trailer wrapper, TV and axis negatives
  reject. Callback identity is checked independently against direct original
  expressions, including swapped model, wrong callback and wrapper negatives.
- No guide fallback: complete strict alias probe sizes range 120–474; guide
  474. Alias names preserve identifier length. `alias-reflow-proof.json` checks
  all 69 declarations' raw scanner tokens/comments after actual formatting,
  code-only reversal, with zero added commas/braces and a separate owned cache.
- 34 new original characterization cases pass, including all four strict macOS
  goldens, with frozen public-parts fixture, source reader and surface namespace.
  The source reader requires one physical owner for every manifest entry;
  final topology activates only from `DETAIL_SHOWCASE_COMPLETE = True`.
- Golden choices: `signal`, null artwork, DPR 1, en-US, text scale 1, January
  dates, host-owned nodes, bounded pumps (600 + 240 ms after frame dispatch).
  `tv_movie`: 1920×1080, original page/dpad, identity focused, trailer absent.
  `compact_series`: 390×844 direct parts (no scroll offset), season pill and
  compact episode. `wide_series_bands`: 1280×2600 direct fixed-column parts,
  metrics `w=1280`, `compact=false`, `touch=false`, k=1, all promised bands
  asserted in capture bounds. `compact_guide`: 390×844, category 1 open.
  Initial capture was only on R; later runs compare without regeneration.
- CI behaviour list gains three direct-importer tests and seven new files. The
  five existing related files remain 69/69 passing. Shape/theme/related guards
  have 197 passes and the unchanged detail-theme raw-colour failure; corrected
  profile-guard run retains the observed profile adapter guard failure. Two
  erroneous test paths in the first invocation are retained as development
  evidence, then rerun at their actual paths; no failure list is changed.
- Architecture, size, CI format, scoped analyzer/12-warning allowlist, new-test
  analyzer and diff checks pass. Source inventory: 18 bare radii, zero shape
  tokens; theme/light ink measurements recorded, classification unchanged;
  shape registrations wait for actual file creation at step 1. Storage member
  map and unrelated application/importer files remain unchanged.
- Linux capture script resolves the exact format and characterization subjects,
  consumes all log output, requires checkpoint application hashes equal R,
  validates Linux/amd64 and Flutter 3.44.8, records image ID/input hashes, then
  captures once and strictly compares the originals. Linux PNGs are exclusively
  staged/committed in L, and Linux becomes strict at L. They are never swept into
  the characterization commit.

### Step 0b — original proofs closed; Linux handoff blocks extraction

- Characterization checkpoint (b): `887b1a8f`, application exactly R
  `1165b624`. `two-originals-proof.json`: `lib` tree
  `283bb5e83f819343c30c08137bf8bf98f899b0c8`, pubspec
  `5f983ff8c68a01aef5c7a1ec393e677e7693591f`, lockfile
  `e0ff9cca69c00ae69bb4dfe111c18a89547cec98` equal at both commits.
- Original proof worktree was owned inside this worktree's ignored
  `.dart_tool/detail_showcase_original`, detached at (b). Both initial and
  restored clean characterization runs pass 34/34, with identical outcomes,
  SDK and committed tree, no untracked inputs or changes during each run.
- `original-b-mutations/step0b-original-mutations.json` records **14 actual
  assertion rejections**:
  lazy hold, dispose order, hold routed to primary, trailer double-fire,
  dropped guide identity, selection not re-seated, TV hover ungated, visibility
  axis dropped, sources browse term dropped, k always one, visible guide radius,
  deleted original declaration, namespace change, and final-topology flag on
  original. All source/guard files restored byte-identically. No compilation or
  loading failure is used as proof; widget TestFailures are classified by the
  runner as `error`, so evidence inspects their actual assertion messages.
- The first radius attempt hit the honors chip outside the scene and passed;
  reject that proof. The corrected unique guide-plate anchor fails the strict
  `wide_series_bands` pixels. Captured diff images are retained under the own
  `golden-mutation-failures/` evidence folder. Successful earlier assertion logs
  are validated/reused; no assertions or goldens are changed to obtain rejection.
  Mutation runner refinements retain all frozen assertions. The final fixture
  audit below adds explicit UTC encoding; every PNG still equals (b). The
  planned Linux strict-default delta is reserved for L.
- **Original base3 is `detail_showcase/base3` on committed ORIGINAL (b).** Full
  suite: 11,127 success, unchanged 13 failure, 28 error, 20 skips. PASS against
  `base-fmt` and `base`: exactly 34 added passing identities; every previous
  identity/outcome unchanged, zero missing/newly skipped/new failures. SDK
  Flutter 3.44.8 / Dart 3.12.2; `paths=[]`, `flags=["--no-pub"]`; tested tree
  `ed509a7c81b3bd2f97c1b60ac4f55c82af282739`, start/end equal, no overlay or
  untracked inputs. Base3 is original evidence, not either extraction gate.
- All **11 manifests with self-tests pass**: detail showcase, settings, IPTV,
  TorBox, Real-Debrid, PikPak, playback settings, IPTV settings, playlist content,
  merged detail and player launch. Every configuration uses its original
  baseline; merged detail specifically `21320ff9`. Runs sharing the owned
  `.dart_tool/detail_showcase_parser` are serialized; the overlapping format/
  alias reflow proof owns `.dart_tool/detail_showcase_probe_parser` and kernel.
  `step0-all-manifests.json` fingerprints the logs.
- Final step-0 checks: architecture 1,261 files; size 2,321 files/173 ratchets;
  CI format, scoped analyzer/12-warning allowlist and whole analyzer comparison
  pass (zero additions/removals). New Dart tests/helpers analyze clean. Four
  macOS originals stay hash-identical; full base3 also passes the existing
  merged `showcase` golden. Source slice remains 18 literal radii/zero shape
  calls; theme `details_themed` remains 65 files/750 sites; light ink 5 candidate
  sites, zero PRIMARY. LF, shell/Python syntax, diff and caller/source-set checks
  pass. No new application seam, suppression, dependency or failure-list entry.
- **BLOCKED at step L:** no Linux originals or
  `linux-original-{capture,strict,sha256,revision,run-url}.txt` provenance are
  present. Do not begin builder moves. No production feature file has been
  created and no declaration moved; current original facade is **3,425 lines**
  (20 import directives occupying 21 lines; 3,404 remaining lines containing
  the 69 declarations/docs/separators). The pure-export facade and its final
  export/comment breakdown remain deliverables for steps 4–5.
- Remaining: L (verify supplied Linux hashes/provenance, separate commit and
  strict Linux default), steps 1–5 and both full-suite extraction gates, each
  compared with the latest original base (gate 2 also with gate 1). Keep all
  found behaviour as documented; only item 3's formatting was resolved as
  explicitly planned.
  Pending device checks: Android TV D-pad through bands/held Play/season popup,
  Apple TV trackpad circles versus cards, merged-shell trailer/play handoff;
  remote CI, completion Linux replay and Claude's integrated-tree checks.
  Branch stays `refactor/detail-showcase`; no push. Stop at this handoff.

### Step 0b UTC fixture audit — new original checkpoint

- Pin episode `firstAired` with `DateTime.utc(2026, 1, n).toIso8601String()`
  to satisfy the plan's explicit UTC fixture rule. The original parts display
  `firstAired.split('T').first`, so the January calendar text is unchanged;
  strict replay confirms all four (b) PNGs without regeneration. No assertion
  is weakened or removed; this is the sole Dart helper delta from (b), outside
  the planned future Linux strict-default change.
- The capture script still uses exactly (b)'s tests, as required. Both encoded
  fixtures render the same original calendar labels; original strict macOS
  PNG hashes stay equal, and the script's application-tree equality rule still
  compares (b) with R. Linux provenance and hashes will be verified separately.
- New original checkpoint: `c74fb2cf` (`test(detail-showcase): step 0b
  original-code proof checkpoint`). `step0b-utc-checkpoint.json` records its
  unchanged R application hashes, frozen assertion/test bodies and macOS PNGs;
  only the explicit UTC fixture and proof-runner refinements differ from (b).
  No feature file or production declaration has been created/moved.
- Detached replay `original-utc-checkpoint` passes **34/34** on that committed
  checkpoint, with a clean, stable input tree; identity comparison with (b)'s
  restored clean run passes. The refined runner then repeats **all 14 mutations
  freshly**, each rejected by an actual assertion, without compilation/loading
  errors or reused logs. Source/architecture files are restored byte-identically;
  strict pixel failure artifacts are retained outside the proof tree. Previous
  (b) mutation evidence remains in `original-b-mutations/`.
- **Latest ORIGINAL base: `detail_showcase/base4` on `c74fb2cf`.** Full suite:
  **11,127 success / 13 failure / 28 error / 20 skipped**. `base4-comparison.json`
  records PASS against base3 (zero added/changed/missing/skipped identities) and
  base/base-fmt (exactly 34 added passing cases, all previous outcomes identical).
  Flutter 3.44.8 / Dart 3.12.2; `paths=[]`, `flags=["--no-pub"]`; tested tree
  `3e9b548859e3d1cfd8ab414963708907cc3e470b`, start/end equal, no snapshot,
  untracked inputs or changes during the run. Both extraction gates must use
  this latest base; neither gate has run. Base4 is original baseline evidence.
- UTC helper/test analyzer, fixture formatting, Linux script syntax and final
  diff checks pass. All previous step-0 application/checker evidence remains
  valid: no application, assertion, manifest, checker configuration, suppression
  or dependency changed after those checks. The final report commit changes
  documentation only; its application/test inputs equal `c74fb2cf`. The final
  document audit restores an accidentally duplicated Progress block in the
  execution preamble; all approved text outside Progress equals `14d173a9`.
- **Step L remains BLOCKED:** all four Linux PNGs and all five required
  provenance files are absent at this handoff. Capture still resolves exactly
  (b) `887b1a8f` and R `1165b624`; do not move builders or sweep future Linux
  inputs into another commit. Steps 1–5, both gates, final facade and device/
  remote CI/integrated-tree checks remain pending. Current original facade is
  still 3,425 lines (21 import lines + 3,404 other lines). Branch unchanged;
  no push, no regression acceptance, no found behaviour fixed beyond the
  authorized formatter cleanup. Stop and report this prerequisite.

### Further step 0b — independent review closure on ORIGINAL

- The independent step-0 review supersedes the earlier golden host and Linux
  capture checkpoint. Keep production application exactly R `1165b624`;
  no builder move, application edit, dependency change or assertion removal.
  New exact capture subject: `test(detail-showcase): step 0b review
  characterization checkpoint`. Record original proofs and latest full-suite
  base after that commit; old bases/proofs remain historical evidence.
- P1 coverage: guide-card D-pad Select reveals then hides the focused category's
  spoilers; recommendation pointer/Select callbacks receive the identical item;
  all eight identity buttons have ordered positions/labels and independent
  pointer/Select callbacks; the real page's action count mounts eight nodes;
  explicit primary refocus dispatches `focused`; wide TV season tapping selects
  the tapped season rather than the current season.
- P2 coverage: hover entry/exit and equivalent keyboard focus lift on source,
  guide, recommendation, universe, DYK entry and DYK remainder cards; hover never
  focuses the node. Compact season popup selected Text uses the actual scoped
  accent, and unselected Text remains white.
- User decision: recapture all four macOS originals with `MergedDetailPalette.bg`
  (`0xFF0B0B0E`, production root Scaffold at
  `merged_detail_root_layout.dart:108`) painted **inside** the capture boundary.
  This captures the real detail surface rather than a white ancestor or a
  transparent boundary. `tv_movie` has seven callback-populated circles, no
  trailer, and keeps primary focus. The separate action test renders all eight.
  Old macOS PNGs are retained in `superseded-macos-capture-887b1a8f/`; Claude's
  old Linux evidence is retained in `superseded-linux-capture-887b1a8f/` and is
  superseded, not usable at L. Original-only capture and subsequent strict
  replay pass; dark compact guide/TV originals inspected visually.
- P3 coverage: unknown severity preserves its uppercase word and all eight
  empty meter segments (card + plate); an initially empty category list mounts
  no band/scrollable in either layout; ambient fade duration is pinned to 550 ms.
  The known focused-to-empty update/clamp edge case remains found-not-fixed.
  Lazy hold/dispose ordering remain **source-guard (S)** class per the plan;
  ambient fade duration is also S. Interaction/hover cases are widget behavior
  tests; golden mutations are pixel assertions. Do not label S as runtime proof.
- The mutation runner adds a recorded negative for every new test, separately
  exercises recommendation pointer/Select, swaps complete Explore/More blocks,
  rewires More, changes the real page action count, drops each card's own hover
  lift, and changes each dark scene's ink. Failure PNGs are archived under the
  run's own evidence namespace and the `failures/` folder is removed after each
  mutation, including error paths; original bytes are restored in `finally`.
- Linux script now independently captures the exact new checkpoint in **two
  clean detached worktrees**, each beginning without Linux PNGs or the other
  checkout's build cache. It compares all four SHA256s and PNG bytes and strictly
  replays both captures before copying files into this worktree. The second
  capture/hash/strict logs and `reproduction=independent-second-worktree-byte-identical`
  provenance supplement the five required files. Application hashes must equal
  R. No early-exit awk or shared parser/kernel cache is introduced.
- Development characterization: 49/49 passing (15 added cases), unchanged
  original application. First severity development run observed two meters;
  the new test was corrected before freezing to assert both and all eight
  segments. Existing frozen assertions remain. `ci_behavior_tests.txt` gains
  only the new identity-actions test. New committed original replay, fresh
  mutation proofs and full-suite latest base are recorded below when complete.

## Found, not fixed

All pre-existing; the move keeps each exactly.

1. `_plateFill` (161) is dead (`unused_element`); its doc describes a
   channel-logo plate no code uses.
2. `kShowcaseGutter` (141) is public and referenced nowhere.
3. The file isn't `dart format`-clean (12 hunks, from `f73f4800` and
   `d05d9d7c`); resolved only by the format-only commit.
4. `_CircleState`'s `MouseRegion` (1256–1259) isn't TV-gated, contrary to
   `_Hover`'s Apple TV trackpad rationale (259–264).
5. `_SeasonDropdownState._open` uses `context` after `await showMenu` and calls
   `selectSeason` without a `mounted` check (1406–1436); the popup's right inset
   `overlay.size.width - origin.dx - 220` can go negative.
6. `_ShowcaseGuideState.didUpdateWidget` would throw on `clamp(0, -1)` if a new
   guide had 0 categories while an old node kept focus (reachability unproven).
7. `ShowcaseIdentity` gates the first two actions on `actionNodes.isNotEmpty`
   (497, 509) and later ones on `i < actionNodes.length`; a short node list
   would make two circles share a node. Latent: `_actionCount` matches.
8. `_Primary` always uses `autofocus: true` (1143), which may interact with
   shell focus restore.
9. `_LogoOrTitle` decodes at a fixed 520 regardless of `k` (789); the sticky
   logo scales with `k`.
10. Raw colours bypass the theme (cast placeholder `0xFF4A4A55`, popup
    `0xFF1B1B1E`, tracker tints, `Colors.white70`, the white `_ink`); the
    `_slotFill` doc says "eight call sites" but there are 4.
11. Presentation calls the platform directly: `PlatformUtil.isTelevision`
    (`_Hover`), `HapticFeedback` (1136), `showMenu` (1406).
12. All user-facing strings are hardcoded English.
13. Only `_CastTile` has `Semantics(button:)`; circles and the guide, DYK and
    source cards have no semantic labels.
14. `ShowcaseMetrics.of`'s fallback depends on the whole `MediaQuery`, so it
    rebuilds on any change.
15. The topology literals (Contract 7) are duplicated across two files with no
    shared source of truth.
