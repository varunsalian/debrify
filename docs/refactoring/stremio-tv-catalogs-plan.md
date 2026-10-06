# Stremio TV local catalogs dialog refactor — plan

Written 2026-10-06 on `refactor/stremio-tv-catalogs`, cut from
`refactor/codebase` at `0cb50df7`. Follow [AGENTS.md](../../AGENTS.md).

Read first: `detail-showcase-plan.md` (closest template: a multi-class file
behind a **pure re-export facade**, private widgets crossing files through
pinned aliases, never renames), `debrify-tv-plan.md` (exact `http` import
pair, size exceptions, step 0/0b discipline), `catalog-detail-plan.md`, and
the Progress sections of those plans. This plan reuses their technique,
checker (`check_verbatim_moves.py` / `check_settings_moves.py`, `sections`
engine, `type_aliases` + opt-in `file_aliases`), `suite_evidence.py`, gate
procedure and integration rules, and states only what differs.

**Execution.** Own worktree
`/Users/varunbsalian/Documents/Projects/debrify-wt/stremio-tv-catalogs` on
`refactor/stremio-tv-catalogs`. Commit after every step; never push, never
merge; gate commits contain `gate`. Evidence only under
`$(git rev-parse --path-format=absolute --git-common-dir)/refactor-evidence/stremio_tv_catalogs/`. **Every manifest run passes an
isolated `--parser-package`** inside this worktree's ignored `.dart_tool/`
(delete any `*.dill` in a copied parser package). `suite_evidence.py` runs
are serialized within the worktree. Four sibling refactors run concurrently
in other worktrees (`stremio_tv_screen`, `stremio_tv_tuner`,
`edit_profile_screen`, `settings_widgets`): a timeout under contention is
rerun, never recorded; load-sensitive flakes are rerun in isolation and
noted, never allowlisted.

## Goal

`lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart` is
2,852 lines, already formatted (`dart format --set-exit-if-changed` exits 0,
so **R = `0cb50df7`**; no format-only commit). It holds five public
top-level classes and eight private declarations (plus States, one private
extension and one private top-level function):

| Lines | Declaration |
| --- | --- |
| 1–18 | 16 import directives |
| 20–53 | `LocalCatalogExportPayload`, `LocalCatalogExporter` |
| 55–393 | section comment; `LocalCatalogImporter` (+ privates `_portableTraktSources`, `_portableImportMetadata`) |
| 395–1020 | section comment; `StremioTvLocalCatalogEditorDialog` + `_StremioTvLocalCatalogEditorDialogState` (626 lines) |
| 1022–1495 | section comment; `StremioTvLocalCatalogsDialog` (statics `show`, `importFrom{File,Url,Json,Repo,Trakt,Mdblist}`, `_showSnackBar`) + State |
| 1497–1520 | section comment; `_backHopsTo` |
| 1522–1746 | `_ImportUrlDialog` + State |
| 1748–1967 | section comment; `_ImportJsonDialog` + State |
| 1969–2514 | section comment; `_TraktListSource`, `_TraktListSourceExt`, `_ImportTraktDialog` + State (546 lines) |
| 2516–2852 | section comment; `_MdblistListCategory`, `_ImportMdblistDialog` + State |

Split it **move-only** into a new feature `lib/features/stremio_tv_catalogs/`
and turn the original path into a **pure re-export facade** of the five
public names. Unchanged: widget trees, runtime type names, keys, `const`
placement, focus-node debug labels, dialog results, snackbar text/durations,
storage writes and their order, http request shape and timeout, log lines.

**Callers stay unchanged.** The only importer is
`lib/screens/stremio_tv/stremio_tv_screen.dart` (`show`, the six `importFrom*`
statics, `LocalCatalogExporter.loadCatalog`,
`StremioTvLocalCatalogEditorDialog.show`). A concurrent sibling refactor moves
that screen into `lib/features/stremio_tv/`; its code keeps importing **this
facade path**, which is therefore this feature's public contract (the
cross-feature rule forbids it importing `lib/features/stremio_tv_catalogs/`
directly). No test imports the file today.

**Why a separate feature.** `stremio_tv` already exists (catalog picker,
editor data, providers) and is being extended by the sibling screen refactor;
a separate `stremio_tv_catalogs` feature keeps registrations disjoint for a
clean sequential merge. A later consolidation into `stremio_tv` is a
non-goal here.

**Not a playback seam.** No player, launcher, native bridge, timer or stream.

## Destination layout

| File | Contents (orig lines) | ≈ lines |
| --- | --- | --- |
| `data/local_catalog_export.dart` | `LocalCatalogExportPayload`, `LocalCatalogExporter` (20–53) | 40 |
| `data/local_catalog_importer.dart` | import-helper section comment, `LocalCatalogImporter` (55–393) | 350 |
| `presentation/legacy_stremio_tv_catalogs/local_catalog_editor_dialog.dart` | editor + State (395–1020) | ≈ 640 — **size exception** |
| `presentation/legacy_stremio_tv_catalogs/local_catalogs_manage_dialog.dart` | manage dialog + State (1022–1495) | ≈ 490 |
| `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | `_backHopsTo` + URL dialog (1497–1746) + aliases | ≈ 265 |
| `presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart` | JSON dialog (1748–1967) + alias | ≈ 235 |
| `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | enum, extension, Trakt dialog (1969–2514) + alias | ≈ 560 — **size exception** |
| `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` | enum, MDBList dialog (2516–2852) + alias | ≈ 350 |

Every file is measured in its creation commit. Non-exception files must be
≤ 500 (checker-enforced). If the manage dialog measures > 500 at creation,
stop and report (no silent exception).

**Size exceptions (move-only cannot split one State).** Registered in
`STREMIO_TV_CATALOGS_SIZE_EXCEPTIONS` at the **measured** creation value
(a ceiling equal to the measurement, not a round number):
- editor dialog: one State (remove flow, D-pad order, card rendering helpers
  that read `context`, `widget` and the State's node list). Splitting the card
  helpers into a widget changes the element tree. **Exit:** a separately
  characterized extraction of the item card into its own widget, with its own
  review.
- Trakt dialog: one State plus the private enum/extension it alone uses; a
  private extension cannot cross files without a rename. **Exit:** the Trakt
  list-source model moves to `models/` with public names in a separately
  reviewed change (rename = behaviour-neutral but not move-only).
Both are in AGENTS' 501–800 band and are single-responsibility.

**Data vs bridge.** `LocalCatalogExporter` / `LocalCatalogImporter` have no
`BuildContext` or Flutter API; they go to `data/` (the checker's data-layer
rules then forbid UI imports; they may import services/storage). The six
dialog files call `StremioCatalogStorage`, `TraktService`, `MdblistService`,
`MdblistListSource`, `FilePicker` and `package:http` directly, so they live in
the named legacy bridge `STREMIO_TV_CATALOGS_BRIDGE =
"lib/features/stremio_tv_catalogs/presentation/legacy_stremio_tv_catalogs/"`,
registered in `LEGACY_PLAYBACK_BRIDGES` with an exit comment (exit: catalog
import/refresh data contracts + Riverpod controllers). `package:http` is
allowed by **one exact pair**, `STREMIO_TV_CATALOGS_URL_IMPORT_HTTP_IMPORT =
(<bridge>/local_catalog_url_import_dialog.dart, "package:http/http.dart")`
(Debrify TV precedent); every other feature file importing `package:http`
fails.

**Aliases, never renames (detail-showcase precedent).** Each cross-file
private stays byte-identical and private in its owner; the owner adds pinned
public aliases immediately after it:
- widgets: `_ImportUrlDialog`, `_ImportJsonDialog`, `_ImportTraktDialog`,
  `_ImportMdblistDialog` → `typedef <Alias> = _X;` (+ a constructor tear-off
  const only if the step 0 probe shows a diagnostic without it; the
  constructors take no parameters);
- function: `_backHopsTo` → `const <alias> = _backHopsTo;` (value alias).

Use sites: the manage dialog's four `const _ImportXDialog()` and the JSON
dialog's `_backHopsTo(` become the aliases; owner-file uses keep the private
name. Registered via `type_aliases` and the opt-in file-aware `file_aliases`
key (owner-local spelling enforced; comments/strings untouched), each entry
added in the step that creates its owner file. Final alias names are fixed at
step 0 by a rename-plus-format probe (no reflow; record in Progress). No alias
is exported by the facade. `_StremioTvLocalCatalogEditorDialogState` (used by
`show`'s `GlobalKey`) and `_showSnackBar` stay file-local.

**Facade.** Only `export 'package:debrify/features/stremio_tv_catalogs/…'
show …;` directives and comments, naming exactly
`LocalCatalogExportPayload`, `LocalCatalogExporter`, `LocalCatalogImporter`,
`StremioTvLocalCatalogEditorDialog`, `StremioTvLocalCatalogsDialog`. Cap =
measured at step 3 (target ≤ 20).

**Imports in new files.** Sorted `package:debrify/…` URIs (relative
`stremio_tv_repo_browser_dialog.dart` becomes
`package:debrify/screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart`),
only what each file uses; no `unused_import`/`unnecessary_import`. The
original's out-of-order relative import (line 16) disappears with the
original; any strict-lint `directives_ordering` info that the original has is
recorded by identity at step 0 and must vanish, not move.

## Contracts that must not change

Pinned by behaviour tests on ORIGINAL code (step 0) and kept passing
unchanged; source guards only where behaviour is unobservable.

1. **Public surface**: five names, signatures, statics and defaults
   unchanged; each declared once, re-exported once.
2. **Importer semantics**: `validate` messages and order; `isTrakt`;
   `transformTrakt` field mapping (`year` int-parse fallback, `overview`,
   `rating`, `poster`, `fanart`, `genres` only non-empty) and type majority;
   `generateId` sanitize + base-36 ms suffix; `import`: invalid JSON, Trakt
   without name, empty Trakt, **mixed Trakt split** into "— Movies"/"— Series"
   with per-name skip, single-type pass-through, duplicate-name rejection,
   portable metadata (`trending/popular/anticipated` keep `traktSource`;
   `liked` needs slug+owner; others dropped); refresh Trakt branches (direct,
   custom, liked list payload shape, unknown source, missing slug, type
   filter, empty-after-filter, update-not-found), refresh MDBList
   (`forceRefresh: true`, failed/incomplete, filter, not-found). Writes go
   through the same storage calls in the same order.
3. **Exporter**: first id+type match (type default `movie`), name trim
   fallback `local_catalog`, two-space JSON.
4. **Editor dialog**: loading → not-found / list; compact `< 700`; initial
   focus on Close after load; D-pad up/down chain Close→rows with
   `ensureVisible` (200 ms, `keepVisibleAtEnd`); Esc/goBack and activate on
   Close pop `_changed`; activate on a row opens the confirm; Cancel keeps;
   Remove persists via `updateStremioTvLocalCatalog`, focuses the next row
   (or previous, or Close); last item removes the catalog, shows the
   "Channel removed…" snackbar and pops `true`; failed update shows the red
   snackbar; barrier tap pops `editorKey.currentState?._changed`; PopScope
   pops `_changed`; node labels `localCatalogEditorClose` /
   `localCatalogEditorRemove$i`; dispose order (close, scroll, rows, super).
5. **Manage dialog**: loading/empty/list states and texts; subtitle
   `· Trakt` / `· MDBList`; refresh only for Trakt/MDBList rows, spinner on
   the refreshing row, all refresh buttons disabled while one runs; refresh
   success/failure snackbars and reload; delete confirm/cancel; D-pad chain
   Close→delete buttons, `_scrollToNode` = `idx * 56` animate 200 ms; Close
   pops `_changed`; labels `close` / `del$i`; dispose order (scroll, close,
   nodes, super). Statics: `show` wraps in `Center`; `importFromFile` (picker
   cancel → false, > 20 MiB → "too large" snackbar, null bytes → "Could not
   read file", importer error → red snackbar, success → "Catalog imported",
   exception → "Failed: …"; `.json` suffix stripped case-insensitively as the
   catalog name); `importFromUrl/Json/Trakt/Mdblist` show the right dialog and
   return `result == true`; `importFromRepo` delegates to
   `StremioTvRepoBrowserDialog.show`; snackbar durations 4 s error / 2 s ok.
6. **URL dialog**: 'Enter a URL', 'Invalid URL', `HTTP <code>`, 'Request
   timed out' (15 s), importer error text, 'Failed: …'; success pops `true`;
   one GET of the trimmed URI; name field forwarded as `catalogName`; D-pad
   map (fields' onUp/onDown, Cancel/Import left/right/up, activate/space);
   `_backHopsTo` sends Esc/goBack/browserBack on a shell field to Cancel;
   Import disabled while loading; submit on the URL field.
7. **JSON dialog**: 'Paste JSON content'; `_handleJsonFieldKey` (Esc→Cancel,
   Up at start/empty→Name, Down/activate at end/empty→Import); success pops
   `true`; Cancel/Import key maps.
8. **Trakt dialog**: unauthenticated → "Sign in to Trakt first in Settings.";
   direct import name `Trakt <label>`, duplicate guard on the three names,
   fetch movies then shows, `traktSource` meta; list sources fetch
   custom/liked lists; list import meta (`custom`/`liked`, slug, listId,
   ownerSlug, owner); missing owner; split save + `generateId`; empty and
   no-IMDB errors; pops `true`. `debugPrint` lines unchanged (source guard).
9. **MDBList dialog**: not connected → "Connect MDBList first in Settings.";
   categories mine/liked/top; duplicate guard; `loadListItems(choice)`;
   failed/incomplete error; `mdblistListId` (+ `mdblistOwner`) meta; split
   save; pops `true`.
10. **Theme/shape**: 4 bare literal radii (orig 880, 1344, 2393, 2758) — one
    each in editor, manage, Trakt, MDBList destinations; `app.shape.*` calls
    unchanged.

Where a branch can't be driven through public behaviour with test seams that
already exist (`ProfilePreferences` fixture, `FilePicker.platform`,
`http.runWithClient`, Trakt/MDBList auth via their stored credentials), it
is classified **S** (source-guard-only) in the step 0 inventory with the
reason; every other item is **B** (behavioural) and needs an
assertion-failing ORIGINAL mutation proof.

## Steps

| # | Work |
| --- | --- |
| 0 | Base evidence; deps report; manifest/config/checker self-test; lint + alias probes; harness, characterization, source reader/guards, mutation proofs; CI list; inventory; commit (b) |
| 0b | Claude's independent review of (b); close gaps on ORIGINAL code before any move |
| 1 | Registration (feature, bridge, http pair, size-exception table empty, shape/CI); move `data/` files; original imports + `export … show` them |
| 2 | Move URL, JSON, Trakt, MDBList and manage dialogs together (all alias users in one step, so the original never uses an alias); register aliases and measured size exception (Trakt). **Full-suite gate 1.** |
| 3 | Move the editor; register its measured exception; original becomes the pure facade |
| 4 | `STREMIO_TV_CATALOGS_COMPLETE = True`, facade rules + cap, TEMP rejection, `checks.yml`, docs path update, size-baseline removal. **Full-suite gate 2.** |

### Step 0

1. **Base.** `stremio_tv_catalogs/base`: full suite via `suite_evidence.py run`
   on untouched `0cb50df7` (paths `[]`, flags recorded separately) +
   whole-repo analyzer, with tree/SDK provenance (Flutter 3.44.8). Reuse is
   not allowed across worktrees: this base is this branch's own.
2. **Deps report** `docs/refactoring/stremio-tv-catalogs-deps.md`: per leaf
   (declaration, section-comment fragment) destination, cross-file private
   references and aliases, service/storage/http/platform touchpoints, State
   reads of `widget`/`context`/`mounted`, and owned resources with dispose
   order.
3. **Checker.** `dev/tool/stremio_tv_catalogs_manifest.tsv` (LF) and
   `stremio_tv_catalogs_checker_config.json` (`engine: sections`,
   `allowed_edits: unchanged`), self-test module
   `stremio_tv_catalogs_checker_test.py`, `--relocate
   lib/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart=lib/features/stremio_tv_catalogs/`.
   Negatives through the real config: changed alias target; alias used in its
   owner file; renamed private class; reworded comment; reordered dispose;
   label text change; timeout changed; a registration ahead of its owner file
   rejected (staging required). Any shared-tool change is opt-in and keyed by
   this feature; every integrated manifest's self-tests stay passing
   unchanged.
   **Alias owners.** Every typedef/value alias (and any constructor tear-off
   the probe requires) is also staged in `additional_owners` in the step that
   creates its owner file; `type_aliases`/`file_aliases` pin target and
   spelling, `additional_owners` authorizes the new declaration (round-1
   probe: five `Unregistered settings destination owner` errors without it).
   **Extension support (round-1 P1).** The sections header pass only finds
   `ClassDeclarationImpl`, so `_TraktListSourceExt` fails as "Widget class
   missing or duplicated" even on untouched ORIGINAL. Add an **opt-in**
   config key (`extension_declarations`, absent from every other config)
   that makes the header/ownership pass accept an `ExtensionDeclarationImpl`
   of exactly the listed names, keeping whole-declaration token comparison
   (comments included), single ownership and duplicate detection. Self-test
   positives: ORIGINAL and the complete split pass; negatives: changed
   extension target type (`on _MdblistListCategory`), renamed extension,
   parser-rejection cases (`extension type`, added `implements`), a
   parseable header mutation `extension _TraktListSourceExt<T> on
   _TraktListSource` that must fail the header/token comparison, member body
   edit,
   extension duplicated in two destinations, extension missing. Every other
   manifest's self-tests pass unchanged.
4. **Probes.** Strict-lint baseline of R under
   `lib/features/analysis_options.yaml` (detached copy in `.dart_tool/`), by
   identity; a throwaway alias probe applying exactly the manifest split,
   aliases and imports must report no new diagnostic (incl.
   `library_private_types_in_public_api`, `unused_element`,
   `unused_import`); anything reported is inventoried by rule/symbol/message.
   Alias names fixed here.
5. **Harness** `test/support/stremio_tv_catalogs_fixture.dart`: profile
   preferences fixture (`test/support/profile_fixture.dart` pattern) seeded
   with catalogs; `AppThemeScope` look; pinned view sizes, DPR 1.0: wide
   1280×800 (editor content 880), compact 600×900 (content 536) **and 714×900
   (editor content 650)**, which separates the `< 700` threshold from a
   `< 600` mutant; recording `NavigatorObserver` / result capture; fake
   `FilePicker` platform restored in teardown.
   **TV configuration.** `TvTextField`'s shell needs TV capability **and**
   `tvKeyboardEnabledCached` (tv_text_field.dart:551): the harness pins and
   restores the existing TV debug overrides and keyboard setting per test;
   Back is tested separately while editing (TvTextField consumes it) and
   while shell-focused (`_backHopsTo` → Cancel), and on non-TV (no shell).
   **HTTP.** URL dialog and Trakt use top-level `package:http` →
   per-test `http.runWithClient(MockClient)`. `MdblistService.instance`
   keeps the `http.Client()` created at singleton initialization
   (mdblist_service.dart:63), so the suite initializes the singleton **once
   inside a suite-owned routing-client zone** before any fixture touches it;
   tests swap the routing handler (recording requests) and call
   `MdblistService.instance.resetProfileScope()` in setUp/tearDown
   (`MdblistListSource` is stateless); the routing client is closed only in
   suite teardown, so no test inherits an
   earlier fixture. The `forceRefresh: true` contract is proven by **warming
   the items cache, changing the response, and asserting refresh issues a new
   request and persists the new items** (a cold cache cannot distinguish
   `false`). Trakt/MDBList auth is seeded through the existing storage setters
   with non-expired Trakt credentials; anything still unreachable is S with a
   reason. Bounded pumps; teardown disposes everything.
6. **Characterization tests** under
   `test/features/stremio_tv_catalogs/` (mirroring destinations):
   `local_catalog_importer_test`, `local_catalog_export_test`,
   `local_catalog_editor_dialog_test`, `local_catalogs_manage_dialog_test`,
   `local_catalog_text_import_dialogs_test` (URL + JSON),
   `local_catalog_list_import_dialogs_test` (Trakt + MDBList),
   `stremio_tv_catalogs_surface_test` (facade namespace = exactly the five
   names, resolved from the original at (b) and from the facade later) and
   `stremio_tv_catalogs_source_contract_test` (guards: log lines, dispose
   order, labels, the 56-px scroll constant, `barrierDismissible: false`,
   `canPop: false`, http timeout). Source reads go through a frozen
   **manifest-driven reader** `test/support/stremio_tv_catalogs_source.dart`
   that picks each declaration from the original or its created destination
   and fails when neither or both hold it. Final-topology checks are dormant
   until `STREMIO_TV_CATALOGS_COMPLETE`. All pass on (b).
7. **Mutation proofs (ORIGINAL).** `dev/tool/stremio_tv_catalogs_original_mutations.py`
   applies each mutation to a scratch copy of (b) and requires a **named
   assertion failure** (not a compile error, not a timeout); behavioural (B)
   and source-guard (S) mutants run separately and are reported apart. At
   minimum: validate message order swapped; `transformTrakt` majority `>=`;
   mixed split not skipping existing; portable metadata keeping `watchlist`;
   `liked` without owner kept; exporter type default changed; editor compact
   threshold 700→600 (killed by the 714-px viewport); editor initial focus on
   the first row; remove focusing `index+1`; last-item path popping `false`
   (and separately `null`) instead of `true`, asserting both the catalog's
   deletion and the returned `true` (a `_changed` mutant is equivalent:
   `_changed = true` precedes the pop); barrier
   pop `true`; manage `_scrollToNode` 56→48; refresh enabled during another
   refresh; Trakt/MDBList subtitle swapped; 20 MiB cap off-by-one
   (`>=`); `.json` strip case-sensitive; snackbar durations swapped; URL
   timeout 15→30 s; `HTTP` message format; `_backHopsTo` dropping
   `browserBack`; JSON field Up-at-start → Import; Trakt direct name format;
   Trakt list meta `custom`/`liked` swapped; MDBList `forceRefresh` false;
   dispose order swapped (S). Results recorded with counts; **every B mutant
   must fail**.
8. **CI list.** Add every new test to `dev/tool/ci_behavior_tests.txt`; no
   known failures expected.
9. **Inventory.** Shape (round-1 P1): the original is in `kShapeResidue`
   with budget 4 and its `app.shape.br*` calls count toward the **exactly
   488** floor. Destinations that contain `app.shape.` calls — URL (2),
   JSON (2), editor (2) — go into **`kShapeResidue`** (so the floor still
   counts them: 488 at every checkpoint); token-free destinations — manage,
   Trakt, MDBList (1 bare radius each), the two `data/` files (0) — go into
   `kExtractedShapeResidue`; each in its creation commit, zero budgets
   included. The original's budget is lowered **4 → 1 (step 2) → 0**, and at
   step 3, when it becomes the export-only facade (no `app.shape.`), its
   entry moves from `kShapeResidue` to `kExtractedShapeResidue` with 0. Each
   checkpoint asserts the aggregate bare-radius count over the original +
   destinations is exactly 4 and the floor count is exactly 488. Theme: `theme_surface_manifest.txt`
   does not cover `lib/screens/stremio_tv/widgets/`; record that the new
   feature is likewise uncovered (no new theme registration, measured
   unchanged). `text_white_sweep.py` excludes `stremio_tv` path parts; the new
   path contains it (verify). `docs/stremio/building-local-catalogs.md:7`
   gets the new path at step 4. No goldens: see Decisions.
10. **Commit (b)** `test(stremio-tv-catalogs): step 0 original-code
    characterization checkpoint`, proving `git rev-parse <b>:lib` equals
    `0cb50df7:lib` and `pubspec.yaml`/`pubspec.lock` unchanged.

### Step 0b

Claude reviews (b) before any move: re-runs a sample of mutants, checks each
B classification is really behavioural, hunts for unpinned branches
(especially focus restoration after remove, refresh concurrency, the
editor's barrier result, URL timeout and Trakt/MDBList save splits), and
lists gaps. Codex closes them on ORIGINAL code in a 0b commit; record
`base` re-run only if tests were added (added identities only, all passing).

### Per step and gates

Every step: this manifest plus every integrated manifest with self-tests
(isolated parser packages); architecture + sizes (lowering the line-21
ratchet in `file_size_baseline.txt`, removed at step 3/4); shape (slice = 4)
and theme; CI format and scoped analyzer with `check_analyzer_allowlist.py`;
strict comparison by identity; the focused characterization set. Gates are
full-suite on committed trees vs `stremio_tv_catalogs/base`; gate 2 also vs
gate 1. Never `--record` a regression.

**Guard rules** (`check_search_architecture.py`, step 1): add
`stremio_tv_catalogs` to `FEATURES` (`FEATURES += ("stremio_tv_catalogs",)`
on its own line, the Debrify TV pattern, to keep the merge additive);
`STREMIO_TV_CATALOGS_FACADE`, `_BRIDGE`, `_COMPLETE = False`,
`_SIZE_EXCEPTIONS = {}` (entries added at measured values in steps 2–3),
`_URL_IMPORT_HTTP_IMPORT`; 500-line limit for the feature except the table;
no facade back-import; no service import outside the bridge except `data/`;
`TEMP(stremio_tv_catalogs)` only inside the bridge before completion;
**feature-wide `package:http/` prohibition** (every layer: data,
application, models, presentation, bridge) except the exact registered
file/URI pair — the generic presentation rule alone lets a `data/` file
import http; no
import of `lib/features/stremio_tv/` (and vice versa) except `models/`. At
step 4: facade in `main()`, `COMPOSITION_ROOTS` comment (pure export surface),
pure-export rule with exactly the five names, measured cap, TEMP rejected
everywhere. A `stremio_tv_catalogs_architecture_test.py` runs the real
`main()` on a temp tree copy and must reject: missing facade; a facade
declaration/import; facade over cap; a sixth exported name; a back-import;
an unregistered `package:http` import in a `data/`, `application/`,
`models/` and another bridge file (four negatives); a bridge file
over its exception; a `TEMP` marker. The unmodified tree passes.

**checks.yml** (step 4): facade path and `test/support/stremio_tv_catalogs_*.dart`
in the format list and the facade in the analyze list — **inside the command,
never after `| tee`**.

## Definition of done

1. Facade: pure re-export of exactly the five names, within its cap;
   `stremio_tv_screen.dart` compiles unchanged.
2. Feature: every file ≤ 500 except the two measured exceptions; cross-file
   privates only through the five pinned aliases; runtime type names
   unchanged.
3. Guards proven through the real checker (incl. negatives above).
4. All manifests + self-tests pass; every (b)/(0b) test passes unchanged.
5. No new diagnostics or suppressions; strict-lint identities traced.
6. CI lists updated; shape slice 4 with facade 0; size baseline entry
   removed; docs path updated.
7. Gate 2 passes vs base and gate 1. Then stop and report.

## Explicitly not in scope

`stremio_tv_screen.dart` and `stremio_tv_tuner.dart` (sibling refactors),
`stremio_tv_repo_browser_dialog.dart`, `StremioCatalogStorage`, Trakt/MDBList
services, the existing `lib/features/stremio_tv/` feature, Riverpod,
localization, and every bug fix below.

## Found, not fixed (recorded; behaviour preserved)

1. Manage dialog has no `PopScope` and default `barrierDismissible`: a barrier
   tap or system Back after a delete/refresh pops `null`, so the screen skips
   its refresh even though catalogs changed.
2. Trakt and MDBList duplicate-guard branches call `setState` after an
   `await` without a `mounted` check (dispose mid-check throws).
3. `_saveAsCatalog` (Trakt/MDBList) and `LocalCatalogImporter.import`'s mixed
   split ignore `addStremioTvLocalCatalog`'s `false`; a fully skipped mixed
   import reports success.
4. Storage writes resolve the profile at write time (no captured scope): a
   profile switch mid-import/refresh writes into the incoming profile.
5. Manage dialog refresh buttons have no focus node in the custom D-pad
   chain; `_scrollToNode` assumes 56-px rows and never scrolls for Close.
6. Editor initial focus is always Close, never the first row.
7. Trakt import `debugPrint`s list names and owners.
8. JSON field is a plain `TextField` (not `TvTextField`) on TV.
9. All user-facing text is hard-coded English (legacy localization
   exception, unchanged extracted text).
10. `refreshTraktCatalog`/`refreshMdblistCatalog` set `addedAt` before the
    empty-items rejection (no write occurs; harmless ordering).

## Decisions taken before design review

- **No goldens.** Every declaration moves whole and byte-identical
  (checker-enforced, comments included); the only edits are import
  directives and five alias identifiers resolving to the same runtime types.
  Rendering is therefore identical by construction; layout facts that matter
  (compact threshold, focus chain, states, texts) are pinned by behaviour
  tests. Goldens would add a Linux capture loop without covering any
  changeable surface.
- Two documented size exceptions (editor, Trakt) instead of non-move edits.
- `data/` for the exporter/importer (UI-free) rather than the bridge.
- Separate `stremio_tv_catalogs` feature, not `stremio_tv`.
- No format commit (original already formatted).

## End-of-series device checklist

- Android TV / tvOS: D-pad through the manage dialog (Close ↔ delete rows,
  refresh rows reachable?), editor (Close ↔ remove rows, scroll-into-view,
  Back), URL/JSON dialogs (`TvTextField` editing, Back hop to Cancel).
- Android file picker import (`.json`, large file rejection).
- Live Trakt (direct, custom, liked) and MDBList imports and refreshes.
- Phone: compact editor layout, snackbars.

## Round 1 review resolution (Codex, session stvcat-design)

1. P1 extension unsupported by the sections header pass → opt-in
   `extension_declarations` key with positives/negatives (Step 0 item 3).
2. P1 shape floor/residue → token-bearing destinations in `kShapeResidue`,
   token-free in `kExtractedShapeResidue`, original 4 → 1 → 0 then moved;
   floor exactly 488 and radii exactly 4 asserted per checkpoint (item 9).
3. P1 equivalent mutant → last-item pop mutated to `false`/`null`, asserting
   deletion and `true` (item 7).
4. P2 `additional_owners` staging for every alias (item 3).
5. P2 714-px viewport; TV capability + keyboard overrides; Back while
   editing vs shell-focused vs non-TV (item 5).
6. P2 MDBList singleton client in a suite-owned routing zone; cache resets;
   warm-cache `forceRefresh` proof; Trakt auth via storage setters (item 5).
7. P2 feature-wide http prohibition with four layer negatives (Guard rules).
8. P3 16 imports; integrator handoff below.

Round 2: all resolved, "No P1s — executable"; its two P3s folded in
(parseable extension-header negative; `resetProfileScope()` as the MDBList
cache owner).

**Integrator handoff (shared files needing union merge + merged-tree
revalidation):** `dev/tool/check_search_architecture.py` (FEATURES via a
separate `+=` line, new constants, `LEGACY_PLAYBACK_BRIDGES`,
`COMPOSITION_ROOTS`, `main()`), `dev/tool/check_settings_moves.py`
(opt-in `extension_declarations`), `test/theme/shape_manifest_test.dart`,
`dev/tool/ci_behavior_tests.txt`, `dev/tool/file_size_baseline.txt`,
`.github/workflows/checks.yml`, `dev/tool/analyzer_allowlist.txt` (if
touched). Round-1 scratch measurements: editor 632, Trakt 554, manage 487,
facade 8.

## Progress

### Step 0 — ORIGINAL characterization checkpoint (2026-10-06)

Execution started at `8316eaefb2268c0e5bb44f824d487643b68ab808`; R/base is
`0cb50df7e767485c6a3f9febd3dec7fb97df1239`. Evidence now resides in
`$(git rev-parse --path-format=absolute --git-common-dir)/refactor-evidence/stremio_tv_catalogs/`
(moved from the worktree-local location during Step 0b). The checkpoint keeps all `lib/`
bytes and both pubspec files identical to R. No Step 1 registration or move.

Base: `base.jsonl` / `base.env.json`, paths `[]`, flags
`--no-pub --concurrency=2 --timeout=120s`, Flutter 3.44.8 / Dart 3.12.2,
tested tree `9a3d396c8b4e99e0f273fde8e8bf4903a70534df`: 11,654 success,
13 failure, 28 error, 20 skipped across 1,138 suites. No runner timeout.
Failure identities are in `base-failures.json`; the WebDAV appearance-policy
failure reproduced in `base-webdav-isolated.jsonl` (51 success, 1 failure),
so it is baseline behavior. No timing flake or allowlist change. Whole-repo
analyzer: 1,687 identical diagnostic identities in `base-analyze.txt` and
`checkpoint-source-analyze.txt`; `analyze-compare.txt` has zero additions.
The explicit source paths avoid duplicate diagnostics from owned scratch
copies; `baseline-notes.json` records that correction.

The 19-leaf manifest, opt-in extension checker, complete-split/negative
self-tests, eight test files, isolated fixture, frozen manifest-driven
reader, resolved namespace check, CI list, and dependencies/inventory are
added. Final aliases: `LcUrlDialog`, `LcJsonDialog`, `LcTraktDialog`,
`LcMdblistDialog`, `lcBackHop`; no constructor tear-off. Strict probe has
zero new diagnostics and removes only the original import-order identity;
no declaration reflow. Scratch measurements: export 38, importer 347,
editor 632, manage 488, URL 264, JSON 230, Trakt 554, MDBList 346, facade 8.
The exact shape assertions retain four bare radii and the 488 floor.

Proof checkpoint: `af3074641a9aa91adbd3b75b0e2336154ed17b55`, tested tree
`1d6fddeb92155ed624864f9cc054f73efd80b110`. `characterization.jsonl` /
`characterization.env.json`: all 94 tests pass across eight suites, paths
`[test/features/stremio_tv_catalogs]`, flags
`--no-pub --concurrency=1 --timeout=120s`; comparison to base adds 94 passing
identities with zero new failures, missing tests, or skips. The final (b)
amendment changes documentation and the mutation reader's load-error
classification; source, tests, manifest, and move checker remain identical
to the proof checkpoint.

ORIGINAL proofs ran B and S in separate serialized invocations with
`--original-worktree .dart_tool/stremio_tv_catalogs_original` and the isolated
`.dart_tool/stremio_tv_catalogs_mutation_parser/.dart_tool/package_config.json`.
Each case records its test path, `--plain-name`, `--no-pub --concurrency=1
--timeout=120s`, SDK/tree provenance, mutated source hash, and named assertion.

| Kind | Cases | Named assertion kills | Survivors | Compile/timeout kills accepted |
| --- | ---: | ---: | ---: | ---: |
| B | 77 | 77 | 0 | 0 |
| S | 10 | 10 | 0 | 0 |

Evidence: `original-B-mutations.json`, `original-S-mutations.json`, per-case
`original-{B,S}-*.jsonl` / `.env.json`, and `mutation-audit.json`. Every failed
identity passed on ORIGINAL; all 87 hashes and trees were audited (only the
original dialog file changes), and the scratch checkout is restored clean.
Mutation probes tightened per-row subtitles, refresh item-count assertions,
and custom/liked split types/items/ID assertions before freezing the tests.
S initially exposed a reader false positive on the assertion literal "Failed
to load lists"; loader failures are now recognized by their prefix. Five
reader probes retain actual load/compile/timeout rejection, all 77 B records
were revalidated, and all ten S cases were rerun (`mutation-reader-self-test.json`).
No real suite timeout was retained or accepted as a kill.

S classifications (details in the deps inventory): disposal order (1: no
existing disposal-sequence callback), logs (2: exact diagnostic text/spacing),
debug labels (1: diagnostic identifiers), disabled MDBList text (1:
compile-time true enablement), service catches (4: non-strict services
convert failures to empty results; no singleton throw-injection seam), and
shape construction (1: source inventory; layouts are behavioral). Other
contract classifications are B. No source guard is counted as a B kill.

Verification: final formatting and scoped analysis pass (zero issues),
CI-equivalent format/analyzer and existing warning allowlist checks pass,
architecture and sizes pass, Python compilation and diff checks pass.
Integrated manifest/self-tests: 17/17 PASS, including this feature’s ORIGINAL,
complete-split, staged-owner, and extension/alias/comment/dispose/label/timeout
negative probes.
All checker invocations use separate in-worktree parser packages with copied
`*.dill` removed. An incomplete merged-detail checker run was discarded when
rescheduling independent checkers into two workers; its replacement passed.
Suite evidence remained serialized. `integrated-checkers.json` records every
command and verdict; no existing test/check/allowlist was weakened or deleted.

Final `lib` tree remains `c529a99209dc591d0a99917b1db90d534e8a4265`, equal to
R; both pubspec blobs are unchanged. Device/emulator/run/install and remote
CI/push/merge were not run, as scoped. FilePicker restores an existing platform
instance; its API cannot restore an initially unset late singleton, so that case
resets to a fresh empty picker (documented in the deps inventory). At (b), Step 0b and
all production moves remained unstarted. No Step 0 check remained pending.


### Step 0b — review closure on ORIGINAL (2026-10-06)

Reviewed (b): `953718d34ef744ccae69f6a691832a5c9c6b9f8a`; proof snapshot:
`0817c27c2af393385c168055cad3c7a5a7cb0c23`, tree
`f6b9eac1212d762a11111241fee4ca08389f864a`. The final amendment adds only
this entry; application code remains original R (`0cb50df7`).

Moved all 349 evidence files, verifying byte hashes before path updates, to
`$(git rev-parse --path-format=absolute --git-common-dir)/refactor-evidence/stremio_tv_catalogs/`.
Artifact names below are relative to that directory. Scripts now resolve/store
common-directory evidence paths, including scratch runs. `.gitignore` matches R;
no worktree-local evidence remains (`evidence-relocation-0b.json`).

`base-additions-0b.jsonl` / `.env.json`: exactly 25 added passing identities,
paths `[test/features/stremio_tv_catalogs]`, flags
`--no-pub --concurrency=1 --timeout=120s --plain-name=review `,
Flutter 3.44.8 / Dart 3.12.2. `base-additions-compare-0b.txt` confirms no new
failures/skips; the full baseline is preserved without a re-record or allowlist
change. `characterization-0b.jsonl` / `.env.json`: same paths/flags without the
name filter, 119/119 pass, all 94 prior identities preserved
(`characterization-compare-0b.txt`). The 25 additions stay in the eight CI-listed
files; existing assertions, harness and manifest-driven reader remain intact.

Review coverage: exact entry targets/results, repo/Center, editor navigation,
confirm identity/ordered writes/focus/dismissal, manage selected deletion and
Found-not-fixed #1, URL/JSON key maps/loading, and Trakt/MDBList routing/texts.
The deps inventory maps these boundaries to the new executable cases.
Aliases remain `LcUrlDialog`, `LcJsonDialog`, `LcTraktDialog`, `LcMdblistDialog`,
`lcBackHop`.

| Kind | New cases | Named assertion kills | Survivors | Compile/timeout kills accepted |
| --- | ---: | ---: | ---: | ---: |
| B | 40 | 40 | 0 | 0 |
| S | 1 | 1 | 0 | 0 |

B and S ran separately from the clean `.dart_tool/stremio_tv_catalogs_original`
proof copy using `stremio_tv_catalogs_review_mutations.json`, `--label review-0b
--positive stremio_tv_catalogs/characterization-0b`, and isolated
`.dart_tool/stremio_tv_catalogs_0b_mutation_parser/.dart_tool/package_config.json`.
`review-0b-{B,S}-mutations.json`, per-case logs and `mutation-audit-0b.json`
record paths/name filters, serialized `--no-pub --concurrency=1 --timeout=120s`,
SDK/trees/hashes/assertions: all 41 trees change only the original dialog file,
every failed identity passes on ORIGINAL, and scratch is restored clean. Prior
77 B / 10 S evidence is retained.

The sole new S is `_onSourceChanged`'s list reset: direct-source UI hides
`_lists`; picker transitions synchronously clear it again in `_fetchLists`,
so dropping that assignment alone is behavior-equivalent through public seams.
Error reset, repo delegation and Center are B.

Format, focused analysis (zero issues), CI analysis/allowlist, architecture,
sizes, Python and diff checks pass (`quality-0b.json`). CI identities remain
325/325 with zero additions/removals; unchanged application/dependencies retain
the recorded 1,687 whole-repo baseline identities. Shape/theme guards pass 13/13.
All 17 integrated manifest self-tests pass, including the feature negatives
(`integrated-checkers-0b.json`); each uses a separate
`.dart_tool/stremio_tv_catalogs_0b_parsers/` copy with copied `*.dill` removed before use.
Suite evidence stayed serialized. An initial shape/theme Git metadata snapshot
was retried before test execution; no failed result was recorded (`run-notes-0b.json`).

`lib` remains `c529a99209dc591d0a99917b1db90d534e8a4265`, identical to R;
both pubspec files are unchanged. No production move or Step 1 work, and no
push/merge/branch switch/device/emulator/run/install. No requested Step 0b check
remains pending. Stop after the 0b commit.

### Step 1 — data moves (2026-10-06)

Parent `103b570a1f225824658420b7704b1ed4705d89ca`; tested/proof commit `387bdbc8ba570b535d0cf49959c376316fc8aa71`,
tree `4d019b4460400d0b0395af2b1e269bb2cb72f753`. Final amendment adds only this Progress entry.
Evidence names below are relative to the common Git directory’s
`refactor-evidence/stremio_tv_catalogs/`.

Measured physical lines: `local_catalog_export.dart` 38, `local_catalog_importer.dart` 347, `stremio_tv_local_catalogs_dialog.dart` 2482.
Registered the feature, legacy bridge, exact URL-dialog/http pair and empty
size-exception table; moved both data owners, preserving their public exports.
Aliases remain unstaged. The existing ORIGINAL extension parser opt-in remains
necessary until its Trakt destination is created in Step 2.

All 19 whole declarations and seven section dividers are byte-identical to R
except the 0 registered alias-use substitutions
(`step1-byte-audit.json`). All 119 characterizations and both support
files are unchanged from 0b; 119/119 pass, paths
`[test/features/stremio_tv_catalogs]`, flags
`--no-pub --concurrency=1 --timeout=120s`. Shape/theme 13/13 pass, paths
`[test/theme/shape_manifest_test.dart, test/theme/source_guard_test.dart]`,
same flags (`step1-{characterization,shape-theme}.jsonl` / `.env.json`).

17/17 integrated manifests + self-tests pass with fresh isolated
`.dart_tool/stremio_tv_catalogs_step1_parsers/` packages and copied
`*.dill` deleted (`step1-integrated-checkers.json`). Architecture/sizes,
29 architecture probes (21 rejections), CI format, scoped
analyzer/allowlist, storage and diff checks pass (`step1-quality.json`).
CI identities 325→325, zero additions after exact source relocation;
strict identities retain both dropdown deprecations, only ORIGINAL directive
ordering disappears (`step1-strict-identities.json`).

Exact shape floor 488, catalogs radii 4 and token calls 6. Original budget
4; original remains in `kShapeResidue`.
Every created destination has its measured budget; theme surface metrics
remain unchanged/uncovered and text-white exclusion remains effective
(`step1-inventory.json`). Suite runs serialized; no allowlist changes,
no re-record, no application-body edits beyond the registered aliases.

The prior turn was externally terminated during the checker sweep. Retained
only 13 completed exit-0 records and reran all four unfinished manifests in
fresh `.dart_tool/stremio_tv_catalogs_step1_restart_parsers/` packages; no
partial result accepted (`step1-restart-note.json`). No check remains pending.

### Step 2 — dialogs and gate 1 (2026-10-06)

Parent `7e42a14a6bab7a0cfc85ef42d0dee80cde93c81e`; tested/proof commit `576f71a6dce305bd9e6892bf0180aae56f278205`,
tree `506d70586c6e2bb9bdff3802618d3af8dcc19500`. Final amendment adds only this Progress entry.
Evidence names below are relative to the common Git directory’s
`refactor-evidence/stremio_tv_catalogs/`.

Measured physical lines: `local_catalog_export.dart` 38, `local_catalog_importer.dart` 347, `local_catalog_json_import_dialog.dart` 230, `local_catalog_mdblist_import_dialog.dart` 346, `local_catalog_trakt_import_dialog.dart` 554, `local_catalog_url_import_dialog.dart` 264, `local_catalogs_manage_dialog.dart` 488, `stremio_tv_local_catalogs_dialog.dart` 639.
Moved manage/URL/JSON/Trakt/MDBList together. Staged all four type aliases,
five file aliases and five additional names in four owner records; the Trakt
extension now has its destination owner. Only the five registered code sites
change: `LcUrlDialog`, `LcJsonDialog`, `LcTraktDialog`, `LcMdblistDialog`,
`lcBackHop`. Registered Trakt’s exact 554-line exception (exit: separately
characterized public list-source model extraction).
The frozen checker self-test is unchanged: a new staged wrapper runs its
ORIGINAL fixtures with creation-stage registrations, then checks actual
production with the active registrations. All original negatives still run.

All 19 whole declarations and seven section dividers are byte-identical to R
except the 5 registered alias-use substitutions
(`step2-byte-audit.json`). All 119 characterizations and both support
files are unchanged from 0b; 119/119 pass, paths
`[test/features/stremio_tv_catalogs]`, flags
`--no-pub --concurrency=1 --timeout=120s`. Shape/theme 13/13 pass, paths
`[test/theme/shape_manifest_test.dart, test/theme/source_guard_test.dart]`,
same flags (`step2-{characterization,shape-theme}.jsonl` / `.env.json`).

17/17 integrated manifests + self-tests pass with fresh isolated
`.dart_tool/stremio_tv_catalogs_step2_parsers/` packages and copied
`*.dill` deleted (`step2-integrated-checkers.json`). Architecture/sizes,
30 architecture probes (22 rejections), CI format, scoped
analyzer/allowlist, storage and diff checks pass (`step2-quality.json`).
CI identities 325→325, zero additions after exact source relocation;
strict identities retain both dropdown deprecations, only ORIGINAL directive
ordering disappears (`step2-strict-identities.json`).

Exact shape floor 488, catalogs radii 4 and token calls 6. Original budget
1; original remains in `kShapeResidue`.
Every created destination has its measured budget; theme surface metrics
remain unchanged/uncovered and text-white exclusion remains effective
(`step2-inventory.json`). Suite runs serialized; no allowlist changes,
no re-record, no application-body edits beyond the registered aliases.

Gate 1: 11773 success / 13 failure /
28 error / 20 skipped; 1146 suites.
Paths `[]`; flags `--no-pub --concurrency=2 --timeout=120s`; Flutter 3.44.8 / Dart 3.12.2.
`gate1.jsonl` / `.env.json` runs on the clean proof commit above.
Compared against base: PASS, zero new failures/missing/new skips;
exactly 119 added passing identities vs base, all frozen characterizations
(`gate1-vs-*.txt`, `gate1-summary.json`).
Gate 1 is complete; Step 3 may proceed.
