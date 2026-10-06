# IPTV settings two-pane refactor — plan

Written 2026-10-06 on `refactor/codebase` at `49c53e2e`. Follow
[AGENTS.md](../../AGENTS.md).

Read first: [stremio-tv-tuner-plan.md](stremio-tv-tuner-plan.md) (closest
analogue: a pure-UI focus-heavy widget, owners record, one-step State move,
step-aware validator, `record_owners`/`record_fields` binder keys) and
[settings-widgets-plan.md](settings-widgets-plan.md) (pure-export facade with
exact `show` lists, theme-surface and light-ink registration of a new feature,
importer compatibility proof). This plan reuses their technique, checker
(`check_verbatim_moves.py` → `check_settings_moves.py`), callback-identity
tooling, `suite_evidence.py` evidence, real-config fixtures, original-code
worktree proofs with assertion-failing mutation negatives, the per-entry
wiring checklist and the Linux-golden handoff. It states only what differs.
The facts inventory accompanies this plan and is copied into the dependency
report ([iptv-settings-two-pane-deps.md](iptv-settings-two-pane-deps.md)) at
step 0.

**Execution.** Own git worktree `../debrify-wt/iptv-settings-two-pane` on
branch `refactor/iptv-settings-two-pane`, cut from `refactor/codebase` at
`49c53e2e`, in parallel with four other refactors (spotlight live timeline,
Premiumize files, recordings page, AllDebrid files) and possibly the
`edit_profile` merge. **This branch never edits any file of
`lib/features/iptv_settings/`, `iptv_settings_page.dart`, or any other
`lib/screens/settings/` page.** Run `flutter pub get` first; the lockfile must
not change (Flutter 3.44.8 / Dart 3.12.2). Commit after every step; never push
or switch branches; gate commits contain `gate`. Evidence goes only under
`<git-common-dir>/refactor-evidence/iptv_settings_two_pane/`. Every manifest
run passes an isolated `--parser-package` under the ignored
`.dart_tool/iptv_settings_two_pane_parser/` (delete `*.dill` in copies).
Original proofs use a detached worktree under
`.dart_tool/iptv_settings_two_pane_original/`. `suite_evidence.py` runs are
serialized in this worktree, with `--no-pub` and an explicit `--concurrency`
recorded in the env file. Load-sensitive flakes (UDP remote pairing, Xtream
ingest, Stremio catalogs MDB refresh, WebDAV shard, the 180 ms PIN test) are
rerun in isolation and recorded as a NOTE, never allowlisted. Every new
self-test and checker must also pass from a fresh normal `git clone` (where
`.git` is a directory) after `flutter pub get`; nothing copies `.git` as a
file.

## Goal

`lib/screens/settings/iptv_settings_two_pane.dart` is 2,231 lines and
formatter-clean: 11 imports and these declarations — the public
`iptvAutoRefreshLabel`, `iptvAutoRefreshExplanation`, `IptvAutoRefreshDialog`,
`IptvSettingsTwoPane` (52 documented properties) and
`IptvSettingsTwoPaneState` (1,278 lines: 8 fields, lifecycle, two public focus
entry points, rail and ten panes), the private sealed `_Dest` family (11
classes), and eight private widgets (`_RailHeading`, `_RailEntry`,
`_PaneHeader`, `_Badge`, `_StatStrip`, `_QuietBanner`, `_RowGroup`,
`_PaneRow`, `_MethodCard`, three of them stateful). It is the wide IPTV
settings layout used on TV, desktop and wide tablets: a D-pad rail of sources
and settings, where focusing an entry previews its pane and RIGHT/OK enters it.

Split it into a new feature, `lib/features/iptv_settings_two_pane/`, **moving
code verbatim**. Unchanged: the element tree, keys (the per-destination
`ListView` key), `const` placement, focus nodes and their debug labels,
traversal policy, key handling, build order and the State lifecycle.

**Why a new feature behind a facade** (D1, D2). `iptv_settings` is registered
COMPLETE with exact caps and checker configs; reopening it would change a
finished migration's registrations for a widget it only consumes through a
public constructor. Its seven files (and `iptv_settings_page.dart`, and three
tests) keep importing the facade path unchanged. Cross-feature imports between
`iptv_settings_two_pane` and `iptv_settings`/`settings`/`iptv`/
`settings_widgets` are forbidden outside `models/` (the generic rule already
does this; a named ban makes it explicit).

**Temporary exceptions and their exits.**

| Exception | Exit |
| --- | --- |
| Bridge section reading `IptvSourceStatsLoader.read` (synchronous catalog DB read in a widget, `_syncStats`) | An IPTV source-stats contract provided by the IPTV settings data layer |
| Bridge files importing storage constants (`StartupIptvStorage`, `IptvAppearanceStorage`) and `IptvListMeta` | Startup/appearance option models in `models/` |
| Bridge files importing `lib/screens/settings/iptv_style_page.dart` (`kIptvStyleChoices`, `iptvStyleLabel`) | Style choices moved to a shared model |
| Legacy English text | Localization migration |
| Widget and State under `legacy_iptv_settings_two_pane/` with section/owner wiring | Riverpod two-pane state keyed by route instance |

## Public surface (unchanged)

The facade keeps exporting exactly five names: `IptvAutoRefreshDialog`,
`IptvSettingsTwoPane`, `IptvSettingsTwoPaneState`,
`iptvAutoRefreshExplanation`, `iptvAutoRefreshLabel`. Every importer (seven
`lib/features/iptv_settings` files, `iptv_settings_page.dart`, three tests)
compiles without edits; `GlobalKey<IptvSettingsTwoPaneState>` keeps the same
type (export preserves class identity). `focusRail()` and `focusAddPane()` keep
their signatures and docs. Nothing private becomes reachable from the facade.

## What it contains (original lines at `49c53e2e`)

| Lines | Area |
| --- | --- |
| 1–11 | Imports |
| 13–79 | Auto-refresh label, explanation, dialog |
| 81–254 | `IptvSettingsTwoPane` |
| 256–301 | `_Dest` family |
| 303–367 | State statics/fields, `initState`, `didUpdateWidget`, `dispose` |
| 369–555 | Initial destination, rail indices, `_syncRailNodes`, `_syncStats`, `_paneNode`, `_focusRail`, `focusRail`, `focusAddPane`, `_selectedRailIndex`, `_destForRail`, `_enterPane` |
| 557–581 | `build` |
| 583–815 | `_buildRail`, `_listsSubtitle`, `_iconFor`, `_railSubtitle` |
| 817–1126 | `_buildPane` (with the inline auto-refresh pane), `_buildSourcePane`, `_sourceMeta`, `_buildAddPane` |
| 1128–1573 | Lists, startup, continue-watching, channel-preview, appearance, player-guide and recording panes |
| 1575–1579 | `_returnToRail`, `_chevron` |
| 1583–1784 | `_RailHeading`, `_RailEntry` + State |
| 1786–1977 | `_PaneHeader`, `_Badge`, `_StatStrip`, `_QuietBanner`, `_RowGroup` |
| 1979–2119 | `_PaneRow` + State |
| 2121–2231 | `_MethodCard` + State |

**State and resources.** One static (`_panePoolSize = 24`), seven instance
fields (`_app` late, assigned in `build`; `_dest`; `_railNodes` grow-only;
`_paneNodes` 24 eager nodes labelled `iptv-2p-pane-$i`; `_railScroll`;
`_stats`; `_statsSignature`). No timers, subscriptions, `setState` or
`mounted` in the State except `focusAddPane`'s post-frame `mounted` guard.
Host-owned: the three method focus nodes. `_PaneRowState` lazily owns a
fallback node and disposes it. The State never calls `setState`; all pane and
rail rebuilds come from the two `ValueListenableBuilder`s on `_dest`.

## Contracts that must not change

Pinned by source guards (whole bodies, comments included, through a
per-declaration source reader `test/support/iptv_settings_two_pane_source.dart`
that reverses manifest renames and registered substitutions) and, where
observable, by behaviour tests.

1. **Lifecycle (verbatim with receiver-only qualification).** `initState`:
   `super` → `_syncRailNodes` → `_syncStats` → `_dest.value = openAddSource ?
   const _AddDest() : _initialDest()`. `didUpdateWidget`: `super` →
   `_syncRailNodes` → `_syncStats` → re-home to `_initialDest()` only when the
   current `_SourceDest` id is gone. `dispose`: rail nodes → pane nodes →
   `_railScroll` → `_dest` → `super.dispose()`. The owners record is created
   eagerly as a State field initializer (the 24 pane nodes and the scroll
   controller exist from State construction, as today).
2. **Grow-only rail nodes.** Nodes are added, never removed, while the rail
   grows; `_focusRail` is bounded by `_railCount` and the pool length, so a
   spare is never focused. Test: shrink the playlist list while a removed
   entry's node is still in the old tree (the existing test at
   `iptv_settings_two_pane_test.dart:379`), then grow again and assert node
   identity for surviving indices.
3. **Stats cache.** `IptvSourceStatsLoader.read` runs per playlist only when
   the signature (id, url, serverUrl, username, `password.hashCode`, epgUrl,
   plus `refreshingIds`) changes. Behavioural proxy: with a seeded FFI catalog
   DB (the `iptv_settings_fixture.dart` setup), change the catalog under an
   unchanged signature and rebuild → rail subtitle keeps the old count; then
   change only the password or `refreshingIds` → the new count shows.
4. **Rail order, indices and D-pad grammar.** Entry order for every flag
   combination (sources 0/1/3 × appearance on/off × recording on/off):
   sources, Add, Channel lists, Startup channel, Channel preview, Continue
   watching, [Appearance], Player guide, [Recording], Auto-refresh. UP/DOWN
   neighbours per entry; UP at the first entry is **not consumed** (escapes to
   the page); DOWN at Auto-refresh **is consumed**; RIGHT and
   enter/select/space enter the pane; LEFT is ignored in the rail; KeyRepeat
   behaves like KeyDown; pointer tap only focuses (never enters); hover does
   nothing; focusing an entry previews its pane (`_destForRail`) and scrolls
   the entry to centre.
5. **Pane entry and return.** `_enterPane`: on Add, the method node chosen by
   `addMethod` (0/1/2, default URL); elsewhere the first pane node that is
   attached and `canRequestFocus` (the Favorites row is skipped). LEFT from any
   pane row (and from the URL method card) returns to `_selectedRailIndex`
   (a source pane returns to that source, never to index 0). `focusRail()`
   targets the selected entry; `focusAddPane()` enters immediately when Add is
   already showing, otherwise switches and enters on the next frame (mounted
   guard).
6. **Pane content and keys.** One `ListView` per destination keyed
   `source:<id>`/`add`/`lists`/…/`auto-refresh` (separate scroll positions);
   source pane rows by playlist kind (URL, Xtream, local file, read-only/shared,
   credentials redacted), stats strip vs quiet banner, badges, hidden-count and
   guide subtitles, busy refresh row focusable with a neutered tap; empty
   playlists render the Add pane; startup rows only when enabled, pick-channel
   row only when pinned; recording subtitles across `showEngineToggle` ×
   `recordingEngineEnabled` × `scheduledCount`; battery row only when non-null.
7. **Pieces.** `_PaneRow`: `canRequestFocus = onTap != null`,
   `descendantsAreFocusable: false`, fallback node created lazily and disposed,
   LEFT → `onLeft`, OK → `onTap`, pointer tap focuses the **provided** node then
   calls `onTap`, trailing wrapped in `IgnorePointer` (a Switch tap fires once).
   `_MethodCard`: LEFT, RIGHT (null → consumed), DOWN, OK; tap focuses then
   taps. `_RailEntry`: as contract 4. Focus visuals are live
   (`focusNode.hasFocus`), never cached.
8. **Callback identity.** Function objects passed through unchanged:
   `Switch.onChanged: widget.onToggleStartup`,
   `widget.onToggleTrackContinueWatching`, `widget.onToggleChannelPreview`,
   `widget.onToggleRecordingEngine`; `onTap: widget.onPickAutoRefresh`,
   `widget.onCreateList`, `widget.onManageChannelOrder`,
   `widget.onPickStartupChannel`; method cards' `onDown:
   widget.onFocusFirstFormField` and `onRight/onLeft:
   widget.<x>MethodFocusNode.requestFocus`. Tests compare these with the host's
   closures by `identical`. State tear-offs (`_enterPane`, `_returnToRail`)
   become cached-section tear-offs; tests assert equality across two builds
   (a tear-off of one cached receiver is `==`).
9. **Layout.** Rail width 400 at `MediaQuery.sizeOf(context).width >= 1400`,
   else 330; `FocusTraversalGroup(WidgetOrderTraversalPolicy)`; 1 px divider;
   the theme read once per `build` into `_app`.
10. **No new responsibilities.** No feature or facade file imports `http`,
    `shared_preferences`, `sqflite`, a player, `player_launch`, native bridges
    or profile services; the only data read stays `_syncStats`. No new
    `Builder`, `KeepAlive` or wrapper widget; no `const` change (113 `const `
    lines).

## Destination layout

All under `lib/features/iptv_settings_two_pane/presentation/`; each file at
most 500 formatted lines; no size exception expected. The step 0 dependency
report settles exact membership from actual references; this is the frozen
member map.

**Outside the bridge (service-free whole declarations, public names):**

- `iptv_auto_refresh_dialog.dart` — `iptvAutoRefreshLabel`,
  `iptvAutoRefreshExplanation`, `IptvAutoRefreshDialog` (names unchanged).
  ≈ 70.
- `iptv_two_pane_destination.dart` — `_Dest` → `IptvTwoPaneDest` (sealed, so
  the whole family stays in one library), `_SourceDest` →
  `IptvTwoPaneSourceDest`, `_AddDest` → `IptvTwoPaneAddDest`, and so on for all
  eleven. ≈ 50.
- `iptv_two_pane_rail_entry.dart` — `_RailHeading` → `IptvTwoPaneRailHeading`,
  `_RailEntry`/`_RailEntryState` → `IptvTwoPaneRailEntry`/`…State`. ≈ 210.
- `iptv_two_pane_pane_parts.dart` — `_PaneHeader`, `_Badge`, `_StatStrip`,
  `_QuietBanner`, `_RowGroup` → `IptvTwoPanePaneHeader`, `IptvTwoPaneBadge`,
  `IptvTwoPaneStatStrip`, `IptvTwoPaneQuietBanner`, `IptvTwoPaneRowGroup`.
  ≈ 200.
- `iptv_two_pane_row.dart` — `_PaneRow`/`_PaneRowState` → `IptvTwoPaneRow`/
  `IptvTwoPaneRowState`. ≈ 150.
- `iptv_two_pane_method_card.dart` — `_MethodCard`/`…State` →
  `IptvTwoPaneMethodCard`/`…State`. ≈ 120.

**`legacy_iptv_settings_two_pane/`** (the bridge; may import the stats loader,
the two storage-constant classes, `iptv_media_store.dart` with exact `show`
lists, and `iptv_style_page.dart`):

- `iptv_settings_two_pane_widget.dart` — `IptvSettingsTwoPane` (byte-identical,
  including every doc comment and the constructor) and
  `IptvSettingsTwoPaneState` with: the owners field (eager initializer), the
  cached sections (nullable cached field with a getter, never per build and
  never `late` initialised in `build`), the verbatim lifecycle, `focusRail`,
  `focusAddPane` and `build` with receiver-only rewrites. ≈ 320.
- `iptv_settings_two_pane_owners.dart` — `IptvSettingsTwoPaneOwners`: the
  static `_panePoolSize` (still private; only the pane-node initializer reads
  it) and the seven fields renamed by dropping the underscore (`app` stays
  `late`), docs and initializers verbatim. ≈ 45.
- `iptv_settings_two_pane_dependencies.dart` —
  `IptvSettingsTwoPaneDependencies`: `widget()` (live: the State's current
  `widget`), `context()` (live), `owners`, `sections()`; and
  `IptvSettingsTwoPaneSections`, which constructs every section once in a
  fixed order (constructors only store `_deps`). ≈ 70.
- Sections (each `final IptvSettingsTwoPaneDependencies _deps;` plus **only
  the one-line getters it uses** among `IptvSettingsTwoPane get widget =>
  _deps.widget();`, `_owners` and `_sections`; an unused getter would be a new
  warning):
  - `iptv_settings_two_pane_navigation.dart` —
    `IptvSettingsTwoPaneNavigation`: `_initialDest`, `_railCount` and the six
    index getters, `_syncRailNodes`, `_syncStats`, `_paneNode`, `_focusRail`,
    `_selectedRailIndex`, `_destForRail`, `_enterPane`, `_returnToRail`.
    ≈ 230.
  - `iptv_settings_two_pane_rail.dart` — `IptvSettingsTwoPaneRail`:
    `_buildRail`, `_listsSubtitle`, `_iconFor`, `_railSubtitle`. ≈ 250.
  - `iptv_settings_two_pane_panes.dart` — `IptvSettingsTwoPanePanes`:
    `_buildPane`, `_buildSourcePane`, `_sourceMeta`, `_buildAddPane`,
    `_chevron`. ≈ 330.
  - `iptv_settings_two_pane_list_panes.dart` — `IptvSettingsTwoPaneListPanes`:
    `_buildListsPane`, `_buildStartupPane`. ≈ 170.
  - `iptv_settings_two_pane_preference_panes.dart` —
    `IptvSettingsTwoPanePreferencePanes`: `_buildContinueWatchingPane`,
    `_buildChannelPreviewPane`, `_buildAppearancePane`,
    `_buildPlayerGuidePane`, `_buildRecordingPane`. ≈ 310.

Members called only inside their own class keep their private names.
Cross-class members get manifest-listed public names: `initialDest`,
`syncRailNodes`, `syncStats`, `paneNode`, **`focusRailAt`** (not `focusRail`,
to avoid confusion with the State's public `focusRail()`),
`selectedRailIndex`, `destForRail`, `enterPane`, `returnToRail`, the index
getters the rail reads (`channelPreviewIndex`, `continueWatchingIndex`,
`appearanceIndex`, `playerGuideIndex`, `recordingIndex`, `autoRefreshIndex`),
`buildRail`, `iconFor`, `buildPane`, `chevron`, and every pane builder the
`buildPane` switch calls.

**The facade** becomes a pure export file: the five names in one or more
`export '…' show …;` directives with the original top-of-file shape, measured
at completion (expected ≤ 12 lines).

**Guard registration** (`check_search_architecture.py`, step 1):
`iptv_settings_two_pane` in `FEATURES`; `IPTV_SETTINGS_TWO_PANE_FACADE`/
`_BRIDGE`/`_COMPLETE = False` (→ `True` at step 3), `_FACADE_CAP`,
`_PUBLIC_NAMES` (exactly five); the bridge in `LEGACY_PLAYBACK_BRIDGES` (still
no `http`, `shared_preferences`, `sqflite`); the service-free files must not
import `lib/services/`; no facade back-import; the named cross-feature ban
above; at completion the facade in the pure-export facade list (the
`SETTINGS_WIDGETS_FACADE`/`STREMIO_TV_CATALOGS_FACADE` precedent: only `export
… show` directives and comments, exact names, destinations inside the
feature) and in `main()`'s facade paths. Real-checker tests (temporary tree
copy) in `dev/tool/iptv_settings_two_pane_architecture_test.py` must reject: a
missing facade, a facade with a non-export declaration, a sixth or missing
exported name, an export from outside the feature, `TEMP(iptv_settings_two_pane)`
anywhere after completion, a service import in a service-free file, a facade
import from the feature, an `iptv_settings` implementation import from this
feature and the reverse, and any destination at 501 lines; the unmodified
tree passes. Run at every step and in CI.

## Technique

As in the tuner and Debrify TV plans, plus:

1. **No format commit.** The file is formatter-clean, so R is the untouched
   base head; checkpoint (b) `test(iptv-settings-two-pane): step 0
   original-code characterization checkpoint` leaves application files equal
   to R (`git rev-parse <b>:lib` = `<R>:lib`, plus `pubspec.yaml`,
   `pubspec.lock`) and adds tests, harness, source reader, checker config and
   macOS goldens.
2. **Strict-lint baseline and rename probe.** As tuner Technique 2: analyze R
   under `lib/features/analysis_options.yaml` in a detached worktree and a
   throwaway rename/receiver probe of the full step-2 shape; inventory by
   identity (expected: `use_key_in_widget_constructors` infos for the
   now-public key-less widgets; nothing else). No key parameter, constructor,
   `const` or suppression change. Surviving **warnings** get an
   `analyzer_allowlist.txt` entry by destination identity in the commit that
   creates the file (none expected).
3. **`widget` through a token-preserving live getter.** Each section declares
   `IptvSettingsTwoPane get widget => _deps.widget();` where the dependency is
   the State's own closure `() => widget`, evaluated on every call. Every moved
   `widget.<p>` site therefore stays token-identical and `unbound` in both
   ASTs; no typed view interface is needed because the widget class is public
   and lives in the same feature (D2). The source contract pins each getter's
   exact one-line body. Negatives: a cached widget snapshot, a stored copy, a
   getter returning another object, any facade import.
4. **State `context`.** The two State-context sites in moved section code —
   `MediaQuery.sizeOf(context)` in `_buildRail` (586) and the three form
   builder calls in `_buildAddPane` (1120–1122) — become `_deps.context()`
   (registered `live_getter_callbacks`). **Lexical scopes stay lexical**: the
   rail's `ValueListenableBuilder` builder parameter `context` (591) and
   `build`'s builder (574, which stays in the State). The existing context
   guard applies; negatives replace the lexical builder `context` with
   `_deps.context()` and the reverse.
5. **Owner fields and the occurrence binder (existing opt-in keys only).**
   Every moved field reference is receiver-qualified (`_owners.dest`,
   `_owners.railNodes`, `_owners.app`, …), including in the State's lifecycle
   and `build`. Reuse batch-2 keys, adding none: `record_owners:
   ["IptvSettingsTwoPaneState"]`, `record_fields:
   {"IptvSettingsTwoPaneState": [the seven instance fields]}` (so the static
   `_panePoolSize`, read bare inside the owners record, is not a record field),
   `occurrence_type_renames: true` for the `_Dest` family and the private
   widget/State renames. Hazards to prove with real moved bodies in step 0b:
   the rail builder's parameter `dest` beside the field `_dest`
   (`_owners.dest`); the local functions `styleIcon` and `option` inside the
   appearance and player-guide panes (block-scoped declarations stay bare
   `decl:` references); `row` counters (`_paneNode(row++)` →
   `_sections.navigation.paneNode(row++)` with `row` lexical). Negatives: a
   bare owner field in a section; a lexical `dest` replaced by
   `_owners.dest.value`; `option` replaced by a section member.
6. **Callback identity, split by shape** (tuner Technique 7). The
   `torbox_callback_identity.py` mechanism covers direct tear-offs and
   single-call arrow closures: `onSelect`/`onRight: _enterPane` (rail),
   `onLeft: _returnToRail` (every pane row and the URL method card), the rail
   `onUp`/`onDown` closures (`() => _focusRail(...)`), `onFocused` closures
   (`() => _dest.value = …`), and every pass-through of a host function object
   (contract 8). Block closures (`focusAddPane`'s post-frame callback, the
   pieces' `onFocusChange`/`onKeyEvent` bodies) are covered by whole-body
   verbatim comparison with receiver-swap negatives.
7. **Verbatim comments.** The checker compares comments; never reword, move or
   drop one, including the `// ---- rail` / `// ---- pane` / `// ---- pieces`
   banners, which travel with the first member below them (the pieces banner
   with `IptvTwoPaneRailHeading`), and the misplaced `_ownFocusNode` doc (Found,
   not fixed).
8. **Shape.** The facade is in `kShapeResidue` at **7** bare radii with **2**
   `app.shape.br` tokens (rail entry). Destinations: rail entry file
   (2 tokens, 0 bare) and every other destination that receives a token or a
   bare radius in **`kShapeResidue`** at its measured ceiling (pane parts 5,
   row 1, method card 1); every other destination and the completed facade in
   `kExtractedShapeResidue` at 0. At every checkpoint the slice holds 2 tokens
   and 7 bare radii in total, and the 488-token floor test passes.
9. **Theme and ink.** `dev/tool/theme_surface_manifest.txt`'s `settings` line
   covers `lib/screens/settings/*.dart` today; from step 1 add
   `lib/features/iptv_settings_two_pane/presentation/*.dart` and
   `…/legacy_iptv_settings_two_pane/*.dart` so the measured surface is
   unchanged (before/after `measure_theme_surface.sh` recorded).
   `light_ink_inventory.py` gets the feature directories next to
   `lib/screens/settings` (the settings_widgets precedent); verify the
   inventory output is identical. `theme_rendered_set.py` keeps its root.
10. **Source-text inventory.** Verify unaffected or update by registration
    only: `file_size_baseline.txt:30` (entry removed when the facade shrinks),
    `shape_manifest_test.dart:218`, `ci_behavior_tests.txt:117`,
    `test/theme/source_guard_test.dart`, `profile_source_guard_test.dart`,
    `stale_runtime_guard_test.dart`, `storage_member_map.tsv`, and every
    `iptv_settings` checker/reader (they name only that feature's own
    `legacy_iptv_settings/iptv_settings_two_pane.dart`, a different file).
    `checks.yml` (step 3): the facade and `test/support/iptv_settings_two_pane_*`
    into the format and analyze lists **before `| tee`**, plus the
    architecture test step.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; lint/rename probes; dependency report; manifest, config, callback sites; harness, characterization tests, source reader, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Independent review (Claude); original-only mutation proofs; compiling-composition probe of the step-2 shape with the real checker and strict analyzer; `base2` at (b) | Nothing moves |
| L | **Before anything moves:** Linux originals hash-verified, committed separately, Linux golden test made strict | Goldens |
| 1 | Guard registration and architecture test (with its CI-registered source-contract runner); dialog, destination family and the four piece files; the facade (still holding widget and State) imports them; shape/theme/ink/CI registrations begin. **Full-suite gate 1** | 4–9 (pieces), 10 |
| 2 | The widget and the whole State in one step: owners, dependencies, sections composition, navigation, rail and the three pane sections; verbatim lifecycle, `focusRail`, `focusAddPane` and `build` with receivers; the facade becomes the pure export file. Nothing is left half-moved, so no temporary forwarder exists | 1–9 |
| 3 | Completion: `IPTV_SETTINGS_TWO_PANE_COMPLETE = True`, measured facade cap, pure-export facade checks, `main()` path, real-checker negatives, CI format/analyze paths, final evidence. **Full-suite gate 2** | All |

**Why step 2 moves the whole State at once.** The State's methods call each
other across every planned section (`_buildRail` → `_focusRail`,
`_destForRail`, `_enterPane`, index getters, `_iconFor`, `_railSubtitle`;
every pane → `_paneNode`, `_returnToRail`, `_chevron`; lifecycle →
`_syncRailNodes`, `_syncStats`, `_initialDest`; `focusRail`/`focusAddPane` →
`_focusRail`, `_selectedRailIndex`, `_enterPane`). Moving them over several
steps would need temporary forwarders; moving all members and fields in one
reviewed step avoids them. Every leaf is still a manifest row with one
destination. Step 0b's compiling-composition probe builds this exact shape on
a scratch tree first.

### Step 0

1. **Baselines.** `iptv_settings_two_pane/base` on the untouched worktree head:
   `suite_evidence.py run` plus the whole-repo analyzer with tree and SDK
   provenance.
2. **Dependency report** (`iptv-settings-two-pane-deps.md`): for every leaf
   the destination; reads of `widget` (by property), `context` (State or
   lexical), `mounted`, owner fields, statics; tear-offs; and a wiring
   checklist entry. It confirms there is no `setState`/`this` in any moved
   State body and lists the cross-class call graph that decides public names.
3. **Checker.** `dev/tool/iptv_settings_two_pane_manifest.tsv` (LF) and
   `iptv_settings_two_pane_checker_config.json`, real-config fixtures and
   `iptv_settings_two_pane_checker_test.py` with a `__main__` that parses
   `--parser-package`. **Step-aware destinations** through the existing
   opt-in `source_validator_module` + `validate_with_context` hook and the
   `scaffold_activation_step` filter (both added by the tuner; reuse, don't
   duplicate): given `completed_step` S, every destination and scaffold for
   steps ≤ S must exist and future files may be absent; retained rows (the
   facade's exports from step 2) and moved rows are distinguished from the
   manifest. Fixtures run S = 0…3 in one process and prove: deleting an
   activated destination fails; restoring a moved leaf to the facade fails; a
   retained export missing fails; an absent future file passes. Negatives
   (each must fail): a reordered or dropped dispose step; `focusAddPane`'s
   post-frame callback made immediate or its `mounted` guard dropped; the
   grow-only loop made to shrink; `_focusRail` bound by the pool length only;
   a section built per build; the owners record built lazily or per build; the
   stats signature missing a field; a reworded comment; a new or removed
   `const`; the Technique 3–5 negatives.
4. **Harness** (`test/support/iptv_settings_two_pane_fixture.dart`): pumps
   `IptvSettingsTwoPane` directly with every property explicit; recording host
   callbacks; host-owned method focus nodes disposed in teardown; playlists of
   every kind (URL, Xtream, local file, read-only shared, credentials
   redacted); `AppThemeScope` with a named look; pinned `tester.view` size and
   DPR; bounded pumps (the busy spinner never settles); D-pad through
   `sendKeyEvent`/`sendKeyDownEvent`+`sendKeyRepeatEvent`; mouse through a
   `TestPointer` of kind mouse for hover/click. Stats cases reuse the
   `iptv_settings_fixture.dart` FFI catalog setup (seed one catalog, close and
   reset in teardown). No `pumpAndSettle` in any test that shows a busy row.
5. **Characterization tests** under
   `test/features/iptv_settings_two_pane/presentation/legacy_iptv_settings_two_pane/`,
   one group per contract, written against R and frozen in (b); each passes
   in a detached worktree of (b) before extraction. The existing
   `iptv_settings_two_pane_test.dart`, `iptv_auto_refresh_settings_test.dart`
   and `iptv_spotlight_style_settings_test.dart` stay unchanged and keep
   importing the facade.
6. **Goldens.** The existing `iptv_settings/wide_two_pane` golden (through
   the page) stays. New deterministic scenes from (b) through the harness,
   1280×800 DPR 1.0, pinned look, `en-US`, text scale 1.0, no DB (sources show
   the quiet banner): Add pane with the file method selected; Channel lists
   with two lists; Startup enabled and pinned; Recording (engine on, three
   scheduled, battery row present); Appearance; Player guide; a source pane
   with the rail entry focused; Auto-refresh; and one 1440×900 scene for the
   400 px rail. Two captures in reversed order must be byte-identical.
   Execution captures macOS in (b); Claude captures Linux (step L).
7. **CI list and known failures.** Add the new tests and the golden test to
   `ci_behavior_tests.txt`. A Dart test
   `iptv_settings_two_pane_source_contracts_test.dart` runs the checker test
   (from (b)) and, from step 1, the architecture test, each with an isolated
   parser package under `.dart_tool/`, asserting exit 0, with a positive
   control proving a broken fixture fails it. Known failures only by identity
   if `base` observes them (none expected).
8. **Linux capture script** `dev/tool/capture_iptv_settings_two_pane_linux_goldens.sh`
   (the tuner script is the template), resolving (b) and R by exact subject
   and failing unless their application hashes match.

### Step 0b (before any extraction)

Claude reviews step 0 independently. On (b), each ORIGINAL-only mutation must
make a **named assertion fail** (behavioural where observable, otherwise
recorded as source-guard-only with the reason): `_railCount` +7 → +6;
Appearance/Player-guide mapping swapped in `_destForRail`; `openAddSource`
ignored; `_initialDest` choosing the first source over the default; the
deleted-source re-home removed; the signature missing the password hash or
`refreshingIds`; grow-only made to shrink; `_focusRail`'s `_railCount` bound
removed; `_enterPane` without the `canRequestFocus` check; Add entry choosing
the URL node regardless of `addMethod`; `focusAddPane` entering before the
pane switches; UP at the top consumed; DOWN at the bottom ignored; KeyRepeat
dropped in the rail, rows or method cards; rail pointer tap calling
`onSelect`; hover changing the pane; `_selectedRailIndex` returning 0 for
sources; `_PaneRow` always focusable; `IgnorePointer` removed (double fire);
the busy refresh tap not neutered; the provided node not focused on tap;
method-card RIGHT at the end not consumed; rail width threshold 1400 → 1200;
the per-destination `ListView` key removed; the empty-playlist guard removed;
startup and recording row conditions; a host function object wrapped in a
closure (identity). It also runs the compiling-composition probe (the full
step-2 shape with real bodies, under the strict config, through the real
checker CLI) and records the facade measurement. `base2` at (b) must pass with
only added, passing identities.

### Per step and gates

The tuner procedure applies with `--baseline <R>` and
`--relocate lib/screens/settings/iptv_settings_two_pane.dart=lib/features/iptv_settings_two_pane/`.
Every step runs: per-entry wiring review; **all integrated manifests plus this
one** with self-tests and isolated parser packages; the occurrence-binder,
context and callback-identity checks; the per-symbol relocation comparison
(zero additions beyond the probe inventory); the architecture test; sizes;
storage references; shape (2 tokens, 7 bare radii, floor ≥ 488), theme and
ink (unchanged); CI format and scoped analyze with the allowlist; LF
manifests; staged diff; all characterization tests and the three existing
two-pane tests; strict macOS and Linux goldens (new and the existing
`iptv_settings` set). Gates run serially on committed trees against the latest
base; gate 2 also compares against gate 1. A first gate failure is
investigated as a possible extraction regression before any flaky acceptance.
Never `--record` or `--update` to accept a regression.

### Integration (Claude)

Claude merges after the sibling refactors in whatever order they finish,
integrating shared files **semantically, by union**:
`check_search_architecture.py`, `check_settings_moves.py`,
`occurrence_field_bindings.py` (no new keys from this branch),
`shape_manifest_test.dart`, `ci_behavior_tests.txt`,
`ci_behavior_known_failures.txt`, `analyzer_allowlist.txt`, `checks.yml`
(paths before `| tee`), `file_size_baseline.txt`,
`theme_surface_manifest.txt` (`settings` line), `light_ink_inventory.py`.

## Definition of done

1. **Facade** is a pure export file of exactly the five names, within its
   measured cap; every importer compiles unchanged.
2. **Guard**: feature, exact bridge, caps, pure-export facade checks, `main()`
   path, the import bans, each proven through the real checker; every
   destination at most 500 lines.
3. **Tests**: all manifests pass with self-tests; every characterization test
   and source guard from (b) passes unchanged; the three existing two-pane
   tests and the `iptv_settings` suite pass unchanged; macOS and Linux goldens
   match the originals.
4. **Diagnostics**: no new warning or suppression; every info maps to an
   original or probe-inventoried identity.
5. **CI**: local CI-equivalent checks pass; behaviour list holds the new
   tests; shape slice 2 tokens and 7 bare radii, floor met; theme and ink
   unchanged.
6. **Progress** records R, (b) and each step's commit, ownership, exceptions
   with exits, and the end-of-series device checklist.
7. **Gate 2** passes against the latest base and gate 1. Then stop and report.

## End-of-series device checklist (no device gate before merge)

- Android TV: rail D-pad walk with key repeat/hold across many sources; UP at
  the top escaping to the page back button; DOWN stopping at Auto-refresh;
  RIGHT/OK entering each pane; LEFT returning to the owning entry; Back via
  `focusRail()`; the IPTV page's "Add playlist" deep link via `focusAddPane()`.
- Android TV performance: rail moves on a weak box (no stats re-read per
  move).
- tvOS focus on the rail and panes; desktop click (select without entering),
  hover (no pane change) and wide (≥ 1400 px) rail.

## Explicitly not in scope

`lib/features/iptv_settings/` and `iptv_settings_page.dart`; every other
`lib/screens/settings/` page (including `iptv_style_page.dart`);
`IptvSourceStatsLoader`, `IptvCatalogDb`, storage classes, models,
`AppThemeScope`; Riverpod, data contracts, localization; behaviour fixes.

## Found, not fixed

1. `_PaneRow.isLast` is passed by every pane but never read (no last-row
   treatment exists).
2. The `_PaneRowState` doc "Live, never cached…" sits on `_ownFocusNode`, not
   on `_focused`.
3. `_syncStats` runs synchronous catalog DB reads on the UI thread in
   `initState`/`didUpdateWidget` (one per source when the signature changes).
4. With `onPickAutoRefresh` null the Auto-refresh pane's only row is not
   focusable, so RIGHT/OK from that rail entry focuses nothing.
5. `_PaneRow`'s pointer tap focuses only a host-provided node; rows using the
   fallback node are never focused by a click.

## Decisions taken before design review (Claude, 2026-10-06)

- **D1. New feature, not reopening `iptv_settings`.** `iptv_settings` is
  COMPLETE with exact caps and checker configs; this widget is a separate,
  reusable view it consumes through a public constructor. A new feature keeps
  both migrations independent and needs no edit in `iptv_settings`.
- **D2. Pure-export facade; widget and State move.** Unlike the tuner, the
  widget and State are public, so both can move and be re-exported with class
  identity preserved (`GlobalKey<IptvSettingsTwoPaneState>` unchanged). This
  removes the typed widget view (≈ 100 forwarding lines) and leaves a facade
  of a few export lines.
- **D3. Intra-feature import cycle accepted.** The widget/State file imports
  the sections; sections import the widget file for the `IptvSettingsTwoPane`
  type of their `widget` getter. Dart permits library cycles; the cycle stays
  inside one feature's bridge (no cross-feature cycle). The alternative — a
  view interface implemented by the State — adds ≈ 100 forwarding lines for no
  behavioural boundary. If design review rejects this, fall back to the tuner
  shape (view interface) without changing anything else.
- **D4. No format commit** (formatter-clean).
- **D5. Goldens without a catalog DB.** Stats rendering is pinned by
  behaviour tests with a seeded FFI catalog; goldens stay DB-free and
  deterministic.
- **D6. Public names for pieces without `key` parameters.** Matching the
  tuner; resulting `use_key_in_widget_constructors` infos are inventoried, not
  fixed.

## Progress

(Execution records here.)
