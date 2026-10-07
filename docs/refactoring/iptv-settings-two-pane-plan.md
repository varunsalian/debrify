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
formatter-clean: 10 imports and these declarations — the public
`iptvAutoRefreshLabel`, `iptvAutoRefreshExplanation`, `IptvAutoRefreshDialog`,
`IptvSettingsTwoPane` (54 documented fields) and
`IptvSettingsTwoPaneState` (1,278 lines: 8 fields, lifecycle, two public focus
entry points, rail and ten panes), the private sealed `_Dest` family (11
classes), and nine private widgets (`_RailHeading`, `_RailEntry`,
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
| 1–11 | Imports (10) |
| 13–58 | Auto-refresh label, explanation, dialog |
| 60–254 | `IptvSettingsTwoPane` (doc comment 60–80) |
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
   spare is never focused. Test (round 1 P2-4): with three
   sources, capture the rail nodes at indices **beyond the reduced rail
   count** (for example indices 8–9, which only exist while three sources are
   present), shrink to one source, then regrow to three and assert those same
   surplus node objects are attached again (`identical`); a shrinking pool
   would have disposed and replaced them. The existing test at
   `iptv_settings_two_pane_test.dart:379` stays as the use-after-dispose
   guard. The shrink mutation must fail the new assertion.
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
   guard). Tests (round 1 P2-5) use **instrumented host-owned method focus
   nodes** (a `FocusNode` subclass recording each `requestFocus` call with the
   frame number and whether the node was attached): already-Add → exactly one
   request in the same frame; source → Add → no request before the switch
   frame and exactly one after it, on an attached node; unmount before the
   post-frame callback → no request at all.
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
   widget.<x>MethodFocusNode.requestFocus`. Tests compare **supplied callback objects**
   with the host's closures by `identical`. Freshly obtained tear-offs —
   `FocusNode.requestFocus` on the host nodes and the State tear-offs
   (`_enterPane`, `_returnToRail`) that become cached-section tear-offs — are
   compared with `==` (same receiver and member), including across two builds.
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
no `http`, `shared_preferences`, `sqflite`) **plus feature-specific guards
(round 1 P2-7)**, because that list exempts every `lib/services/` import: the
bridge may import only `lib/services/iptv_source_stats.dart`,
`lib/services/iptv_media_store.dart` (`show IptvListMeta`),
`lib/services/storage/startup_iptv_storage.dart` and
`lib/services/storage/iptv_appearance_storage.dart` (each with its exact
registered `show` list), and `lib/screens/settings/iptv_style_page.dart`
; **each `show` list is registered per destination file and URI with
exactly the names that file uses** (round 2 P2-3): for example the rail shows
`iptvStyleLabel` only and the preference panes `kIptvStyleChoices` only; the
same per-file rule applies to every service import, never a bridge-wide union
(a wider list is an `unused_shown_name` warning). Any other service, screen, player, `player_launch`, native bridge,
`media_kit` or profile import fails. The service-free files must not import
`lib/services/` or `lib/screens/`; no facade back-import; the named cross-feature ban
above; at completion the facade in the pure-export facade list (the
`SETTINGS_WIDGETS_FACADE`/`STREMIO_TV_CATALOGS_FACADE` precedent: only `export
… show` directives and comments, exact names, destinations inside the
feature) and in `main()`'s facade paths. Real-checker tests (temporary tree
copy) in `dev/tool/iptv_settings_two_pane_architecture_test.py` must reject: a
missing facade, a facade with a non-export declaration, a sixth or missing
exported name, an export from outside the feature, `TEMP(iptv_settings_two_pane)`
anywhere after completion, a service import in a service-free file, a facade
import from the feature, an `iptv_settings` implementation import from this
feature and the reverse, an unregistered service import in the bridge
(for example `profile_registry.dart`), a registered service import with a
wider `show` list, a player or `player_launch` import, and any destination at
501 lines; the unmodified
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
6. **Callback identity, split by shape** (tuner Technique 7; round 1 P1-3).
   The `torbox_callback_identity.py` mechanism covers only **genuine
   tear-offs and single-call arrow closures** whose body invokes a dotted
   member: `onSelect`/`onRight: _enterPane` (rail), `onLeft: _returnToRail`
   (every pane row and the URL method card), the **standalone** rail
   `onUp`/`onDown` closures (`() => _focusRail(...)`), Auto-refresh's
   **distinct** `onLeft: () => _focusRail(_autoRefreshIndex)` (845, not
   `_returnToRail`), and every pass-through of a host function object
   (contract 8). **Conditional callback arguments (round 2 P1)** — the source
   entry `onUp: i == 0 ? null : () => _focusRail(i - 1)`, Add's
   `onUp: widget.playlists.isEmpty ? null : () => _focusRail(...)`, Player
   guide's two-closure `onDown: widget.showRecordingSection ? () => … : () =>
   …`, and every other conditional `onUp`/`onDown` (the dependency report
   lists them all) — are outside that checker (its `conditional_member`
   supports direct tear-offs only, `torbox_callback_identity.py:269`); their
   **complete conditional expressions** go into the exact-expression sidecar
   with whole-body and binder coverage and **branch-specific** receiver-swap
   negatives. Both categories are proven at S = 0…3. The rail's
   **assignment closures** (ten sites: the source loop's `onFocused: () =>
   _dest.value = _destForRail(i)` and nine `() => _dest.value = const
   _XDest()` forms)
   are not representable by that checker (an invoked dotted member is
   required); they are covered by whole-body verbatim comparison, the
   occurrence binder (`_owners.dest` qualification) and an **exact
   callback-expression sidecar** (`iptv_settings_two_pane_callback_sites.json`:
   per site, the original and expected destination expression text), with
   receiver-swap negatives (`_owners.dest` → a section field, the dest class
   swapped, the closure hoisted to a cached field). Block closures
   (`focusAddPane`'s post-frame callback, the pieces' `onFocusChange`/
   `onKeyEvent` bodies) are covered by whole-body verbatim comparison with
   receiver-swap negatives.
7. **Verbatim comments.** The checker compares comments; never reword, move or
   drop one, including the `// ---- rail` / `// ---- pane` / `// ---- pieces`
   banners, which travel with the first member below them (the pieces banner
   with `IptvTwoPaneRailHeading`), and the misplaced `_ownFocusNode` doc (Found,
   not fixed).
8. **Shape (round 1 P1-1).** The facade is in `kShapeResidue` at **7** bare
   radii with **2** `app.shape.br` tokens (rail entry), and every
   `kShapeResidue` file must contain `app.shape.`
   (`shape_manifest_test.dart:1543`). So: the rail-entry file (the only
   destination with tokens) goes in **`kShapeResidue` at 0**; pane parts,
   row and method card go in **`kExtractedShapeResidue`** at their measured
   bare-radius ceilings **5 / 1 / 1**; every other destination is in
   `kExtractedShapeResidue` at 0; and the facade **moves to
   `kExtractedShapeResidue` at 0 in step 1**, when its last token leaves with
   the rail entry. At every checkpoint the slice holds 2 tokens and 7 bare
   radii in total, and the 488-token floor test passes unchanged.
9. **Theme and ink.** `dev/tool/theme_surface_manifest.txt`'s `settings` line
   covers `lib/screens/settings/*.dart` today; from step 1 add
   `lib/features/iptv_settings_two_pane/presentation/*.dart` and
   `…/legacy_iptv_settings_two_pane/*.dart` so the measured surface keeps
   the same theme sites: `measure_theme_surface.sh` prints aggregate file,
   line and regex-hit counts, so parity is **equal regex-hit counts per
   pattern** before/after (file and line totals necessarily change), and
   **expression** parity comes from the per-declaration verbatim/relocation
   proof (round 2 P2-4).
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
    `checks.yml` (**step 1**, round 1 P2-6): the facade, the feature and
    `test/support/iptv_settings_two_pane_*` into the format and analyze lists
    **before `| tee`**, and a quick-job step `python3
    dev/tool/iptv_settings_two_pane_architecture_test.py` after `flutter pub
    get` (the settings_widgets precedent), so the architecture guard runs on
    every push from the first move. Step 3 only flips completion flags and
    caps.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `base`; lint/rename probes; dependency report; manifest, config, callback sites; harness, characterization tests, source reader, macOS goldens (two reversed-order captures); checkpoint (b); CI list; source-text inventory; Linux capture script | Nothing moves |
| 0b | Independent review (Claude); original-only mutation proofs; compiling-composition probe of the step-2 shape with the real checker and strict analyzer; `base2` at (b) | Nothing moves |
| L | **Before anything moves:** Linux originals hash-verified, committed separately, Linux golden test made strict | Goldens |
| 1 | Guard registration and architecture test (quick-job CI step plus the behaviour-job source-contract runner); dialog, destination family and the four piece files; the facade (still holding widget and State) imports them; shape/theme/ink registrations and the format/analyze CI paths. **Full-suite gate 1** | 4–9 (pieces), 10 |
| 2 | The widget and the whole State in one step: owners, dependencies, sections composition, navigation, rail and the three pane sections; verbatim lifecycle, `focusRail`, `focusAddPane` and `build` with receivers; the facade becomes the pure export file. Nothing is left half-moved, so no temporary forwarder exists | 1–9 |
| 3 | Completion: `IPTV_SETTINGS_TWO_PANE_COMPLETE = True`, measured facade cap, pure-export facade checks, `main()` path, real-checker negatives, verification of the step-1 CI paths, final evidence. **Full-suite gate 2** | All |

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
   `--parser-package`. **Row model (round 1 P1-2).** The manifest has
   **one whole-class row** for `IptvSettingsTwoPane` (byte-identical,
   destination the widget file) and **member rows** for
   `IptvSettingsTwoPaneState`: the **eight field rows** (seven instance fields
   and the static) → `IptvSettingsTwoPaneOwners`; `initState`,
   `didUpdateWidget`, `dispose`, `focusRail`, `focusAddPane`, `build` → the
   widget file's State; every other member → its section. The State's new
   owners field and sections cache are **registered scaffolds** (round 2
   P2-2). Never a whole-State row combined with member rows;
   the State **header** (`class IptvSettingsTwoPaneState extends
   State<IptvSettingsTwoPane>`) is checked separately by the validator.
   Whole-class rows for the dialog, the `_Dest` family and each piece. At
   completion **every original leaf is a moved row**; nothing is "retained"
   in the facade. The tuner's facade-only `lifecycle` registration and
   `byte_identical_declarations` (`check_settings_moves.py:1312`, `:1133`)
   look only at the facade, so they are **not registered** for moved
   declarations; instead the source contract pins the lifecycle bodies and
   the widget's bytes at their destination. **Exports** are not declaration
   leaves (the adapter reports them separately), so the feature validator
   (existing opt-in `source_validator_module` + `validate_with_context`, both
   added by the tuner; reuse, don't duplicate) checks the facade's export
   directives from step 2: exactly the five names, each from its registered
   destination, no other declaration. Section-only bans on inherited State
   access (`mounted`, `setState`, `this`) apply to **section files only**, so
   the moved State's own `focusAddPane` `mounted` guard stays accepted.
   **Step-aware destinations** use the same hook and the
   `scaffold_activation_step` filter: given `completed_step` S, every
   destination and scaffold for steps ≤ S must exist and future files may be
   absent. Fixtures run S = 0…3 in one process and prove: deleting an
   activated destination fails; restoring a moved leaf to the facade fails;
   a missing, extra or wrongly sourced export fails from S = 2; the State
   header changed (superclass, an added interface or mixin) fails; an absent
   future file passes. Negatives
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

## Round 1 review resolution

1. **P1 shape** → Technique 8: only the rail-entry file (tokens) in
   `kShapeResidue` at 0; pane parts/row/method card in
   `kExtractedShapeResidue` at 5/1/1; the facade moves to
   `kExtractedShapeResidue` at 0 in step 1.
2. **P1 row model** → Step 0 item 3: one whole-widget row, State member
   rows, separate header check, every leaf moved at completion, exports
   validated by the feature validator from step 2, facade-only lifecycle/byte
   registrations not used, section-only inherited-access bans.
3. **P1 assignment closures** → Technique 6: identity checker only for
   tear-offs/call closures (Auto-refresh's distinct `onLeft` inventoried);
   assignment closures through whole-body, binder and an exact
   callback-expression sidecar with receiver-swap negatives.
4. **P2 grow-only** → contract 2: surplus-node identity across
   shrink/regrow.
5. **P2 post-frame and tear-offs** → contracts 5 and 8: instrumented nodes
   for the three `focusAddPane` cases; `identical` only for supplied objects,
   `==` for fresh tear-offs.
6. **P2 CI ordering** → Technique 10 / step 1: format/analyze paths and the
   architecture quick-job step at step 1.
7. **P2 bridge boundary** → guard registration: exact allowed service/screen
   imports with `show` lists and real-checker negatives.
8. **P3** → counts (10 imports, 54 fields, nine private widgets), line spans
   (dialog 13–58, widget doc from 60) and theme parity by site.

## Round 2 review resolution

1. **P1 conditional callbacks** → Technique 6: complete conditional
   `onUp`/`onDown` expressions in the exact-expression sidecar with
   branch-specific negatives; standalone call closures stay in the identity
   checker; both proven at S = 0…3.
2. **P2 field rows** → Step 0 item 3: eight field rows to the owners record;
   lifecycle/focus/build rows to the widget file; owners field and sections
   cache registered as scaffolds.
3. **P2 `show` lists** → guard registration: per destination file and URI.
4. **P2 theme evidence** → Technique 9: regex-hit parity per pattern plus the
   verbatim proof for expressions.
5. **P3** → Auto-refresh `onLeft` at 845; ten assignment sites (one loop, nine
   constant); step 3 only verifies CI paths.

## Progress

### Step 0 — original-code characterization (2026-10-07)

R is `6c0a609962f673616c08aed513ccf4e5f04d59ed`. Checkpoint (b) is
resolved by the exact subject `test(iptv-settings-two-pane): step 0
original-code characterization checkpoint`; its hash and original application
object equality are recorded after commit in `step0-checkpoint.json` under
`refactor-evidence/iptv_settings_two_pane/`. All evidence below stays in that
namespace. No application file has changed: the facade remains 2,231 lines,
`lib` is `7d84002d0eac9b5acc023d922759dd335d321e94`, `pubspec.yaml` is
`5f983ff8c68a01aef5c7a1ec393e677e7693591f`, and `pubspec.lock` is
`e0ff9cca69c00ae69bb4dfe111c18a89547cec98`.

- `flutter pub get` was the first command involving Flutter. Flutter 3.44.8 /
  Dart 3.12.2 and the resolved lockfile are unchanged. `base.jsonl` is the
  untouched R full suite: paths `[]`, flags `--no-pub --concurrency=2`, stable
  HEAD/tree, 12,030 successful identities, 13 failures, 30 errors and 20 skips.
  The complete failure identities are in `base-failures.json`. Two load-sensitive
  errors are notes, not accepted regressions: Xtream 50k ingest passed with
  unchanged assertions in isolation at 29 seconds (`--timeout=3m` after another
  default-timeout run failed); MDBList category loading passed in isolation.
  The WebDAV appearance assertion `imported_launch_animation_v1` still fails
  in isolation. No failure/analyzer allowlist was changed. Step 0b's `base2`
  must supersede this baseline for both gates; a timeout must never conceal a
  subsequently reintroduced failure. See `baseline-notes.json` and the note logs.
- Whole-repo analyzer baseline: 917 errors, 95 warnings, 706 infos; step-0
  comparison: 917 errors, 91 warnings, 701 infos, **zero added diagnostic
  identities**. Existing errors are confined to patched package tests and the
  tvOS package library; removed diagnostics concern generated assets and
  duplicate infos. The seven new Dart files analyze with zero issues. Strict
  original analysis has eight Radio deprecation infos; the full-shape lint
  probe has 19 infos and zero errors/warnings. The inventory freezes maxima
  per rule/original symbol/message: eight existing deprecations, nine public
  key-less widget infos, the cached-sections recursive-getter info and the
  receiver-qualified guard's formatter-related flow-control info (tuner
  precedent). No key, constructor, `const`, body or suppression fix was made.
- The dependency report freezes all 73 original leaves: one whole widget,
  eight State fields, 38 other State members and the whole dialog/destination/
  piece declarations. Seven instance fields use the existing record binder;
  the static stays excluded. The actual local functions are `styleIcon` and
  `styleRow` (the plan's `option` name was stale). The exact URI scan finds six
  direct feature importers plus the page's relative import and three tests;
  composition is the seventh participating feature file. These consumers are
  unchanged. Live widget/context closures, eager owners and cached sections
  are frozen in 27 step-2 scaffolds. A strict-probe missing label import was
  corrected, and scaffold-only section fields use `listPanes`/
  `preferencePanes`; moved-body tokens are unchanged.
- The callback sidecar freezes 115 full expressions, including ten assignment
  sites and complete conditional branches. Seventy-three supported direct
  tear-off/single-call sites use the existing identity checker. Real-config
  schedules S = 0…3 check activation, moved-leaf uniqueness, exact exports,
  State headers, lifecycle/timing/focus/signature/const/comment mutations,
  callback receiver swaps/wraps/hoisting and lexical binder hazards through
  both checker and reader. Constructor `this._deps` is a legal plain-section
  field binding; the inherited-State token ban applies to methods/getters,
  with a `this.widget` negative. Callback mutations copy only the affected AST
  node; all named assertions remain intact.
- Characterization fixes every public property and borrowed method node,
  with bounded pumps, recorded frame/attachment timing, mouse/repeat input,
  surplus-node identity and seeded-FFI stats caching. The new set is 70
  behavior cases, nine strict macOS goldens and 75 source/tooling contracts.
  Existing tests are unchanged: 15 two-pane, seven auto-refresh and seven
  appearance tests passed in R's full suite, as did all 124 `iptv_settings`
  feature identities, three shape guards and ten theme source guards. The
  existing reachable `wide_two_pane` golden passed separately in a normal
  clone. Fixture/checker development failures are discarded preliminary runs;
  final accepted logs and detached-(b) replay are recorded before extraction.
  The spare-node assertion also checks that the ignored request stays ignored
  after reattachment. It passed against original code. Normal-clone source
  contracts passed 75/75; its final manifest CLI and both analyzer-inventory
  CLI probes passed. The deliberately broken fixture failed the named Dart
  runner assertion (`Expected: 0 / Actual: 1`), not compilation or a timeout.
- Nine original macOS PNGs use the named Spotlight look, `en-US`, DPR 1,
  scale 1, pinned dimensions and real bundled Inter/Poppins/JetBrains Mono/
  Material Icons. The bundled Roboto asset is HTML (already identified by the
  typography tests), so the host explicitly uses Inter. Initial Ahem captures
  were discarded; final forward/reverse captures have identical SHA-256 maps
  and strict comparisons pass. No catalog DB is used in golden scenes.
- CI lists all five new test files. Source-text inventory, original theme
  regex hits (0 / 2 / 1), ink output and shape evidence are retained. The
  original slice still has two `app.shape.` sites and seven bare radii; the
  global 488 floor passes unchanged. Shape/theme/ink/workflow/architecture
  registrations remain step 1 work. The executable Linux capture script
  resolves R/(b) by exact subject, rejects application/hash/SDK/platform/lock
  mismatches, captures nine originals twice in reverse order, verifies hashes,
  then performs a strict comparison. `bash -n` passes; Linux capture is Claude's
  handoff, not a macOS-generated substitute.
- All 295 pre-existing shared tool/config files (excluding the additive CI
  list) are byte-identical to R. No adapter, shared checker, key mechanism or
  existing manifest changed. Each manifest invocation uses an explicit isolated
  parser package below this worktree's `.dart_tool`; no parser package or
  `.git` file was copied. Normal-clone checks run after `flutter pub get` with
  `.git` a directory. Full-suite evidence runs are serialized.

All 20 manifest/self-test CLI runs pass (19 pre-existing plus this one), with
isolated parser packages; `integrated/results.json` records every command and
exit 0. The accepted logs, formatter/diff/link checks, unchanged shared-tool
blob audit, strict inventories and repeatable golden hashes are retained in
the evidence namespace. The frozen detached-(b) replay and application object
equality are recorded there after commit, before any extraction, following the
tuner handoff procedure.
All five found-not-fixed items and every temporary exception/exit remain as
written above. Step 0b (independent review, ORIGINAL-only named-assertion
mutation proofs, real-checker compiling-composition/facade measurement and
`base2`), step L, steps 1–3 and both full-suite extraction gates have not begun.
Device remote repeat/hold, weak-box stats performance, tvOS focus, remote CI
and merged integration remain pending. STOP POINT 1 applies after the committed
and verified checkpoint; resume only after Claude's review/findings.

### Step 0b — independent review follow-through (2026-10-07)

Claude's original-code review rejected 34 of 42 sampled mutants through named
assertions, two through goldens only, and identified six survivors. The added
review file closes the observable gaps on the ORIGINAL application: all 12
source-count/appearance/recording combinations check every focused entry's pane
header and ListView key; retained production source-focus callbacks after a
source-list shrink also exercise `_destForRail`'s settings branches (ordinary
settings entries use direct destination callbacks). Hidden-category counts
0/1/2 pin exact wording. Uncached URL/Xtream/local sources pin their exact rail
subtitles, while the existing seeded cache test pins 1/many channel counts.
Rail and tall-pane focus tests pin the centred scroll offset through the
viewport, with entries away from either clamp boundary.

- `step0b-original-positive.jsonl`: 90/90 behavior identities pass, stable
  ORIGINAL checkpoint `7e7006062094559cdf0f33c64216066c8c5dfaf1`, with only test
  and tooling additions. The three unchanged compatibility suites also passed
  (29/29); the initial combined run is preliminary because mutation metadata
  changed during it. No passing assertion was removed. The final frozen
  behavior subset was rerun with stable input evidence.
- `iptv_settings_two_pane_original_mutations.py` follows the tuner's owned
  detached-worktree/evidence procedure. All 39 mutations are rejected: 35 by
  named assertions, four by source guards. The same 90 positive identities
  and all 39 negative cases pass their proof checks from a fresh normal clone
  after `flutter pub get`; `.git` is a directory. Evidence includes actual
  failed assertion identities, reasons, mutated source hashes and tested
  trees. Every mutation restores the original source and preserves pixels.
- Source-only limits, deliberately preserved: Auto-refresh's distinct LEFT
  closure is equivalent to `returnToRail` while its pane is selected; the
  exact-expression sidecar **and** callback-identity utility reject the swap.
  Scroll-controller/notifier disposal order has no observable UI result and
  is pinned by the lifecycle body. The empty-source guard is unreachable in
  a normal frame because `didUpdateWidget` re-homes before pane rebuilding.
  No current pane has an attached-but-unfocusable pool node before a
  focusable one (Favorites has no pool slot; the nullable Auto-refresh action
  is the only row in that pane, and requesting an unfocusable node is a
  no-op). Its eligibility check remains source-guard-only. These are coverage
  limits, not behavior fixes or weakened assertions.
- `mandatory_qualification: true` is explicit inside the existing
  `occurrence_field_bindings` configuration. Its negative produces the
  **Bare owner field reference** diagnostic under both False/True defaults,
  flipped in in-memory module fixtures; positives pass under both defaults.
  The helper recognizes either literal default after integration. The shared
  binder and AST adapter remain unchanged; none of edit_profile's additional
  opt-in keys is used or reimplemented.
- Conservative naming exception to Technique 5: the extracted `_stats` field
  is `sourceStats`, instead of `stats`. Mandatory qualification reserves record
  member names across the feature and otherwise falsely flags the stat-strip
  widget's own, verbatim `stats` field. A unique manifest-listed record name
  preserves both initializers and every read without a shared-tool mechanism
  or an edit to the piece. The accidental generated `IptvTwoPanePaneRow`
  spelling was also aligned with the plan's `IptvTwoPaneRow` before extraction.
  Other record fields keep their planned names. This is an internal rename,
  not a persisted format or public-facade change.
- Full step-2 compiling composition: real CLI accepts all 73 leaves; strict
  analyzer has 19 inventoried infos, zero errors/warnings/additions; runtime
  and strict macOS golden checks pass 128/128. Probe facade is seven physical
  lines, 14 destinations are at most 352 lines. Source hashes, measurements
  and commands are in `step0b-composition-verification.json` and companion
  logs. Original widget bytes, lifecycle, comments, constructors, consts,
  inherited/lexical contexts and live callbacks remain pinned.
- All 19 pre-existing manifests have byte-identical actual adapter output
  against R for their full CLI source sets (748 file inputs), checked by two
  parses and recorded SHA-256 pairs in `other-manifests-adapter-proof.json`.
  All 295 pre-existing shared tool/config files remain byte-identical except
  the additive CI behavior list.
- Root/normal-clone full real-config fixtures pass S=0…3. The final changed
  default-switch helper was additionally rerun in both environments; the
  original full-suite source-contract runner exercises the final whole CLI
  again in `base2`. New test analyzer: zero issues. No shared failure list or
  analyzer allowlist changed. All five found-not-fixed items remain untouched.

`base2` completed at (b) with final strengthened tests/tooling and unchanged
`lib`/pubspec objects: tested tree `2b584de6f6b9bd64ac65ec164b5fc5e4c70bec74`,
paths `[]`, flags `--no-pub --concurrency=2 --timeout=3m`, stable HEAD/tree.
Comparison with `base` passes: 12,206 successes, 13 pre-existing failures,
28 pre-existing errors and 20 unchanged skips; 174 added passing identities,
zero new failures, zero missing identities/suites and zero new skips. Xtream
50k ingest and MDBList category refresh pass in this full run; their previous
load-sensitive errors remain notes and are not accepted failures. This is the
latest original-code base for both extraction gates. The same flags will be
used for both gates; any load-sensitive failure requires an unchanged-assertion
isolated rerun and a NOTE, never an allowlist entry. Whole-repo analyzer
comparison with step 0 also passes with zero added or removed diagnostics.
Step L and application extraction have not begun.

### Step L — committed Linux originals before extraction (2026-10-07)

Step 0b is `d8a1700b9`. Claude's calibrated `debrify-flutter:3.44.8`
`linux/amd64` capture from (b) provides nine PNGs. Every local SHA-256 matches
both first/reverse inventories byte-for-byte; no image was updated. The
Linux test is now strict by default. macOS and clean Linux strict runs both
pass 9/9; removing one PNG in the owned normal clone fails the named
`ORIGINAL golden add_file ready focus and dimensions` assertion with
`Missing ORIGINAL Linux golden`, without a strictness dart-define. Restoration
preserves all nine hashes. The changed test analyzes with zero issues.

The first Docker dependency cache was ephemeral; it was replaced by a
persistent cache inside this worktree's ignored `.dart_tool` and the accepted
strict evidence was rerun cleanly. The normal clone has a `.git` directory
and ran `flutter pub get` with no lockfile changes. Root application and
pubspec objects remain identical to R/(b). Step L commits only originals,
the stricter test and this evidence record. Application extraction starts
after this separate checkpoint.

### Step 1 — pieces and unconditional guards (2026-10-07)

Step L is `55fc98ca0`. All 26 step-1 leaves are wired to their six production
destinations and checked through the source reader and 73-row manifest. The
dialog is 48 lines, destination family 46, rail entry 208, pane parts 193, row
147 and method card 115. The facade temporarily retains the original widget
and State at 1,510 lines; its measured size ratchet is updated. Remaining
responsibility: State lifecycle, resources, navigation, rail and panes. Exit:
step 2's atomic whole-State move and seven-line pure-export facade.

The facade imports the pieces and re-exports the three moved Auto-refresh
names so existing importers retain the five-name API. The CI analyzer caught
the missing partial export in the initial fixture layout; it was corrected
in the facade and fixture generator without editing any importer. That
preliminary focused run was stopped and discarded; the stable rerun passes
against `base2`: 357 successes, the same pre-existing profile
SharedPreferences source-guard failure, no new failures, missing tests or
skips. All characterization/compatibility suites, the unchanged 124-test
IPTV-settings set and macOS goldens pass.

Architecture registration is additive: unconditional feature scans, 500-line
caps, no wrappers/back-imports/forbidden services, named peer bans in both
directions and exact per-destination/URI show lists. The real-main negative
fixtures pass, including when completion is false. Facade completion remains
false and its cap is measured/activated in step 3. CI runs the architecture
proof after pub get and puts every format/analyze path inside its command
before `| tee`. The changed-code CI formatter passes; CI analysis has only
25 existing allowlisted warnings, and the strict slice has 17 inventoried
infos with zero additions. No allowlist was changed.

Shape registrations move only the rail-entry file into `kShapeResidue` (cap
0); other destinations and the facade are in `kExtractedShapeResidue` with
5/1/1 bare-radius caps for parts/row/method and 0 elsewhere. The slice retains
two tokens and seven bare radii; all three shape tests and the unchanged
488 floor pass. Theme regex hits remain 0/2/1, with the new presentation and
bridge globs registered. The earlier original ink artifact measured only
the facade; the full inventory was recaptured on unchanged (b) and is
byte-identical: 774 candidates/200 files, 240 PRIMARY candidates/67 files.
The slice remains at zero candidates. The own manifest is LF; pre-existing
manifests keep their original bytes, including existing CRLF, rather than
being reformatted. Storage reference fixtures, source inventories, explicit
parser packages, document links and staged-diff checks pass. Forbidden files,
models, loaders, storage, themes, pubspec and all importers are byte-identical
to R. All five found-not-fixed items remain unchanged.

All 21 manifests/self-tests pass. The configured-manifest driver originally
omitted the older plain-engine launcher manifest; its isolated original-(b)
and step-1 CLI runs both pass with byte-identical output, as do two complete
adapter parses. The updated driver includes it at subsequent steps. The
20 pre-existing manifests' CLI and actual adapter outputs are byte-identical
to originals; their full source sets and SHA pairs are recorded. Linux
strict comparisons pass 13/13 (nine new scenes plus the four unchanged
IPTV-settings scenes). The architecture proof also passes from the normal
clone with a `.git` directory after pub get. The existing CI tuner analyzer
has nine inventoried infos and zero additions. Gate 1 now follows on the
committed step-1 tree against accepted `base2`, with paths `[]` and the same
three recorded flags. Gate evidence and its commit will be recorded after
completion before step 2.


### Gate 1 — identity comparison and timing notes (2026-10-07)

Step 1 / gate commit is `bf11bc92f`. The full run records paths `[]` and
`--no-pub --concurrency=2 --timeout=3m`, unchanged committed HEAD/tree, and
12,202 successes, 13 failures, 32 errors and 20 skips. Against latest
`base2`, no identity/suite is missing or added and no new skip occurs. The
raw helper comparison is **FAIL** for four transient errors, preserved in
`gate1-vs-base2.txt`; it is not represented as an all-green helper run.

NOTE: search's keyword-cache focus case had not issued its expected request
after the fixture's fixed 150 ms initialization wait. Two MDB duplicate-guard
cases and the MDB category-directory case lacked their mocked choices/results
after bounded async pumps. First failure was investigated before extraction
continued. Entire affected application and fixture files are byte-identical
to original (b); all four failed identities pass unchanged in serialized
isolation (search 4/4, MDB dialog suite 35/35), and both scoped comparisons
with `base2` pass. `gate1-identity-audit.json` and `gate1-NOTE.txt` retain
identities, original hashes, commands and decision. The gate is accepted with
these timing notes and zero unexplained new failures. No timeout, assertion,
allowlist or raw evidence was changed. Step 2 starts only after these reruns.

### Step 2 — atomic widget/State wiring (2026-10-07)

The whole widget and State now use the eight bridge destinations in one move;
all 73 original leaves are wired, and no original declaration or forwarder
remains in the seven-line pure-export facade. Its exact five public names
and original importers are retained. Owners are created eagerly as a State
field initializer; the 24 pane nodes, grow-only rail nodes, scroll controller,
notifier and cached stats retain their ownership and disposal order. The five
sections are cached once, their constructors only store dependencies, and the
widget/context callbacks read live State values. Callback identity, lexical
contexts, comments, consts and constructor bodies remain pinned.

All 15 production facade/destination files are byte-identical to the accepted
step-0b compiling probe (`step2-compiling-probe-byte-parity.json`). Actual
probe/production maximum is 352 lines; the earlier prose figure 351 was a
transcription error, corrected from the retained measurement artifact. Bridge
sizes: dependencies 36, owners 36, navigation 184, rail 304, panes 352, list
panes 169, preference panes 306 and widget/State 309. Six pieces retain step-1
sizes. Every destination is below its unconditional 500-line cap. All eight
new bridge files enter `kExtractedShapeResidue` at 0; the obsolete facade size
baseline entry is removed. Temporary 1,510-line facade retention has exited.

Focused behavior/source/compatibility/unchanged-IPTV checks finish with 357
successes and the same pre-existing profile SharedPreferences source-guard
failure, zero new failures/missing identities/skips versus `base2`, and stable
inputs. Strict macOS and Linux goldens pass 13/13 each. Architecture real-main
negatives, sizes, storage references, CI format/analyze, strict per-symbol
inventory (19 infos, zero errors/warnings/additions), original ink/theme/shape
parity, source reader, scope and diff checks pass. Existing tuner analyzer
inventory also passes with nine infos and zero additions. Forbidden files and
all importers remain byte-identical to R. All five found-not-fixed items and
every documented legacy exception/exit remain unchanged. All 21 integrated manifest/self-test runs pass with isolated parser packages;
the 20 pre-existing outputs remain byte-identical to originals. The normal
clone also passes every current new checker/self-test, including completion
architecture negatives, after pub get with a directory `.git`. Step 2 is
committed before root completion flags are activated.


The fresh normal-clone step-3 completion probe caught three no-op negative
fixtures: their comma-space token expected a one-line facade show list, while
the actual seven-line facade has comma-newline. The replacements now match
the comma token, with every named assertion, no-op rejection and required
real-main diagnostic intact. This changes only completion-negative inputs;
step-2's completion-false checks are unaffected and were rerun explicitly.
The preliminary clone result is retained/discarded as preliminary, and the
corrected completion probe is rerun before activating root completion.


### Step 3 — completion checks (2026-10-07)

Step 2 is `9cee8acf1`. Completion is activated with
`IPTV_SETTINGS_TWO_PANE_COMPLETE = True`, measured facade cap 7 and checker
`completed_step = 3`. The unconditional feature scan remains active even
with completion disabled. The real-main proof passes 94 cases, including
facade presence/purity/exact names and destinations, exact per-file imports,
501-line caps, wrappers, peer boundaries and completion-false scanning. The
step-1 CI paths remain inside format/analyze commands before `| tee`, and its
quick-job architecture proof remains after pub get.

All final checked source/tool/config input bytes match the fresh normal-clone
proof exactly (`step3-fresh-clone-current-input-parity.json`). That clone has
a directory `.git`, ran pub get with an unchanged lock, and passed the full
own manifest/self-tests, source reader, strict analyzer inventory, capture
script syntax and completion architecture proof. Original-only mutation
proofs already passed in a separate normal clone in step 0b; their unchanged
inputs/evidence remain valid. No `.git` file or parser package was copied.
Every parser/kernel package is isolated under this worktree's `.dart_tool`.

Step-3 focused checks again pass against `base2`: 357 successes, the same
pre-existing profile guard failure, zero missing/new/skipped identities and
stable tested inputs. macOS and Linux strict goldens pass 13/13 each.
Architecture, sizes, storage references, CI formatter/analyzer, strict
19-info per-symbol maxima, ink/theme/shape parity, source reader, scope and
staged-diff checks pass. No new errors, warnings, suppression or allowlist
change. The seven-line facade and all 14 destinations retain exact step-2
production bytes. Found-not-fixed and temporary legacy exceptions are
unchanged. All 21 integrated manifests/self-tests pass with isolated parser packages;
the 20 pre-existing outputs are byte-identical to originals. Committed-tree
full-suite gate 2 now follows, comparing with latest `base2` and gate 1. The
existing tuner analyzer also passes with nine infos and zero additions.

Integrator union is limited to seven existing shared files:
`check_search_architecture.py`, `shape_manifest_test.dart`,
`ci_behavior_tests.txt`, `checks.yml`, `file_size_baseline.txt`,
`theme_surface_manifest.txt` and `light_ink_inventory.py`. Shared checker
engines, occurrence binder, AST adapter/parser inputs, analyzer allowlist and
known-failure list remain original bytes. The 20 pre-existing manifests'
complete actual adapter proofs remain valid because their adapter and every
source input still match R exactly, rechecked at step 3 and recorded in
`step3-shared-union-and-immutability.json`. No future edit_profile keys or
parallel mechanism was added. Explicit mandatory qualification continues to
pass/fail its positives/bare-field negative under both in-memory defaults.

Pending after local completion: Android TV repeat/hold/escape/entry/return
and Add deep-link checks, weak-box stats performance, tvOS focus and desktop
input/device checks, remote CI and semantic integration with sibling
refactors. No push, rebase, branch switch or edit of a forbidden application
file has occurred.
