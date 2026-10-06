# Stremio TV local catalogs — Step 0 dependencies and inventory

ORIGINAL: `0cb50df7` (R); execution worktree starts at `8316eaefb2268c0e5bb44f824d487643b68ab808`.
No production move or service change is authorized in Step 0. All paths below
are planned destinations; the original owns every declaration at checkpoint (b).
Manifest: `dev/tool/stremio_tv_catalogs_manifest.tsv` (19 whole leaves, LF).

## Per-leaf dependencies

`widget`, `context`, and `mounted` columns count code identifiers in each whole
declaration, including its methods/closures. Counts identify State coupling;
they are not proposed changes. Cross-file dependencies name the original private
and the fixed alias used only outside its owner.

| Declaration | Destination | Cross-file private references | Data/platform touchpoints | widget/context/mounted |
| --- | --- | --- | --- | --- |
| `LocalCatalogExportPayload` | `data/local_catalog_export.dart` | — | — | 0 / 0 / 0 |
| `LocalCatalogExporter` | `data/local_catalog_export.dart` | — | `StremioCatalogStorage` | 0 / 0 / 0 |
| `LocalCatalogImporter` | `data/local_catalog_importer.dart` | — | `StremioCatalogStorage`, `TraktService`, `TraktItemTransformer`, `MdblistListSource`, `MdblistListChoice` | 0 / 0 / 0 |
| `StremioTvLocalCatalogEditorDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_editor_dialog.dart` | — | `Navigator` | 0 / 5 / 0 |
| `_StremioTvLocalCatalogEditorDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalog_editor_dialog.dart` | — | `StremioCatalogStorage`, `AppThemeScope`, `Navigator`, `ScaffoldMessenger`, `Scrollable` | 6 / 22 / 6 |
| `StremioTvLocalCatalogsDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalogs_manage_dialog.dart` | `_ImportUrlDialog` → `LcUrlDialog`, `_ImportJsonDialog` → `LcJsonDialog`, `_ImportTraktDialog` → `LcTraktDialog`, `_ImportMdblistDialog` → `LcMdblistDialog` | `FilePicker`, `ScaffoldMessenger` | 0 / 31 / 5 |
| `_StremioTvLocalCatalogsDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalogs_manage_dialog.dart` | — | `StremioCatalogStorage`, `Navigator`, `ScaffoldMessenger` | 0 / 12 / 5 |
| `_backHopsTo` | `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportUrlDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportUrlDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | — | `http`, `TvTextField`, `AppThemeScope`, `Navigator` | 0 / 5 / 4 |
| `_ImportJsonDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportJsonDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart` | `_backHopsTo` → `lcBackHop` | `TvTextField`, `AppThemeScope`, `Navigator` | 0 / 5 / 1 |
| `_TraktListSource` | `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_TraktListSourceExt` | `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportTraktDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportTraktDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | — | `StremioCatalogStorage`, `TraktService`, `TraktItemTransformer`, `Navigator` | 0 / 6 / 8 |
| `_MdblistListCategory` | `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportMdblistDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` | — | — | 0 / 0 / 0 |
| `_ImportMdblistDialogState` | `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` | — | `StremioCatalogStorage`, `MdblistService`, `MdblistListSource`, `MdblistListChoice`, `Navigator` | 0 / 6 / 6 |

## Section-comment fragments

Each non-doc divider moves with the following leaf, retaining every byte of its
text. Declaration doc comments stay with their declarations (including links to
private names; alias reversal does not rewrite comment or literal text).

| Fragment | Following leaf / destination |
| --- | --- |
| `// ─── Import helper ──────────────────────────────────────────────────────────` | `LocalCatalogImporter` / `data/local_catalog_importer.dart` |
| `// ─── Edit dialog ────────────────────────────────────────────────────────────` | `StremioTvLocalCatalogEditorDialog` / `presentation/legacy_stremio_tv_catalogs/local_catalog_editor_dialog.dart` |
| `// ─── Manage dialog ──────────────────────────────────────────────────────────` | `StremioTvLocalCatalogsDialog` / `presentation/legacy_stremio_tv_catalogs/local_catalogs_manage_dialog.dart` |
| `// ─── Import from URL dialog ─────────────────────────────────────────────────` | `_backHopsTo` / `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` |
| `// ─── Paste JSON dialog ──────────────────────────────────────────────────────` | `_ImportJsonDialog` / `presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart` |
| `// ─── Import from Trakt dialog ────────────────────────────────────────────────` | `_TraktListSource` / `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` |
| `// ─── Import from MDBList dialog ──────────────────────────────────────────────` | `_MdblistListCategory` / `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` |

## Alias ownership and resources

| Private | Alias | Owner | External user |
| --- | --- | --- | --- |
| `_ImportUrlDialog` | `LcUrlDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | manage statics |
| `_ImportJsonDialog` | `LcJsonDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_json_import_dialog.dart` | manage statics |
| `_ImportTraktDialog` | `LcTraktDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_trakt_import_dialog.dart` | manage statics |
| `_ImportMdblistDialog` | `LcMdblistDialog` | `presentation/legacy_stremio_tv_catalogs/local_catalog_mdblist_import_dialog.dart` | manage statics |
| `_backHopsTo` | `lcBackHop` | `presentation/legacy_stremio_tv_catalogs/local_catalog_url_import_dialog.dart` | JSON dialog |

Each owner adds its typedef or value const immediately after the private;
`type_aliases`, `file_aliases`, and `additional_owners` are staged only when that
file exists. Original owner uses remain private. No constructor tear-off is
required: the actual formatted split has no private-constructor, unused-element,
or unused-import diagnostic. Formatter comparison passes with no reflow edits.

| State | Owned resources in disposal order |
| --- | --- |
| `_StremioTvLocalCatalogEditorDialogState` | `_closeFocusNode.dispose()` → `_scrollController.dispose()` → `node.dispose()` → `super.dispose()` |
| `_StremioTvLocalCatalogsDialogState` | `_listScrollController.dispose()` → `_closeFocusNode.dispose()` → `n.dispose()` → `super.dispose()` |
| `_ImportUrlDialogState` | `_nameFocusNode.dispose()` → `_urlFocusNode.dispose()` → `_cancelFocusNode.dispose()` → `_importFocusNode.dispose()` → `_urlController.dispose()` → `_nameController.dispose()` → `super.dispose()` |
| `_ImportJsonDialogState` | `_nameFocusNode.dispose()` → `_jsonFocusNode.dispose()` → `_cancelFocusNode.dispose()` → `_importFocusNode.dispose()` → `_jsonController.dispose()` → `_nameController.dispose()` → `super.dispose()` |

Trakt and MDBList States borrow their service singletons; they own no timers,
subscriptions, player, launcher or native playback resource. Dialog route
ownership remains with the existing Navigator. Export/import use the same
profile-resolving `StremioCatalogStorage` methods; Step 0 preserves write order
and the known write-time profile behavior. The fixture owns its temporary
registry/cipher, restores FilePicker and TV/keyboard settings, unmounts widgets,
and closes its routing client only in suite teardown. Temporary filesystem roots
are redirected by the existing `ProfileFixture` and removed in teardown.
FilePicker teardown restores the saved instance when one exists. Its public API
cannot unset an initially uninitialized late singleton, so that case resets to a
fresh empty `CatalogPicker`; each test suite runs in its own Flutter test isolate.

## Strict lint and planned registrations

The detached R probe uses `lib/features/analysis_options.yaml` and Flutter
3.44.8 / Dart 3.12.2. Baseline identities:

| Rule | Symbol / message | Split outcome |
| --- | --- | --- |
| `directives_ordering` | repo-browser relative import; “Sort directive sections alphabetically.” | Removed; sorted package imports |
| `deprecated_member_use` | Trakt dropdown `value`; use `initialValue` | Same message at Trakt destination |
| `deprecated_member_use` | MDBList dropdown `value`; use `initialValue` | Same message at MDBList destination |

No new diagnostic or suppression. `alias-probe.json` measures exporter 38,
importer 347, editor 632, manage 488, URL 264, JSON 230, Trakt 554, MDBList 346,
facade 8. These are scratch measurements; actual creation commits remeasure.
Editor and Trakt exceptions remain deferred to Steps 3 and 2. No architecture,
bridge, http pair, size exception, completion flag, or facade registration is
activated in Step 0. The opt-in checker extension name is `_TraktListSourceExt`;
no other config gains that key.

## Characterization classification

B = observable behavior through ORIGINAL public entry points and existing
seams. Every B mutation runs without the source guard suite and must fail its
named assertion; S runs separately. The executable case file is the authority
for mutation id → member → test → assertion, including all minimum mutations.
The immutable source reader chooses exactly one original/destination owner and
reverses only code aliases. Its negative tests reject missing, duplicate, and
double ownership. Final topology assertions are dormant until completion.

| Contract | Classification / characterization boundary | Mutation coverage |
| --- | --- | --- |
| Public surface | B: analyzer-resolved namespace; public entry-point signatures compiled by fixture/tests | `public-surface`; checker also pins whole declarations/signatures/defaults |
| Importer validation / detection / transform / ID | B: exact errors and precedence, first-item detection, tie movie / series majority, year fallback, all optional mapping, genres, sanitized base36 timestamp | `validate-order`, `validate-item-id`, `majority-tie`, `transform-year`, `transform-overview`, `transform-genres`, `transform-id`, `transform-name`, `transform-rating`, `transform-poster`, `transform-fanart`, `majority-series`, `id-radix`, `is-trakt-show` |
| Import and metadata | B: invalid/nameless/untransformable, native default and trim, duplicates, mixed split and existing-side skip, direct/liked portable fields and dropped private sources | `mixed-existing-side`, `portable-watchlist`, `liked-without-owner`, `native-type-default`, `duplicate-name-error` |
| Trakt refresh | B: direct/custom/liked routing, movie-before-show, listId/ownerSlug/owner fallback, filtering, missing/unknown source and slug, empty/filter-empty, missing stored catalog | `refresh-trakt-slug`, `refresh-trakt-filter`, `refresh-liked-listid`, `refresh-liked-ownerslug`, `refresh-trakt-empty`, `refresh-trakt-notfound` |
| MDBList refresh | B: warm-cache bypass, new request/new persisted items, type filtering, failed/partial, missing ID, empty/filter and missing catalog | `mdb-force-refresh`, `mdb-incomplete` |
| Export | B: first id+type match, absent type movie, trim/fallback, two-space JSON, missing result | `export-default`, `export-fallback`, `export-indent` |
| Editor | B: loading/not-found/list, content widths 880/536/650, Close focus, up/down/select/Back and scrolling, confirm cancel, update/failure, successor/predecessor focus, last delete+true, barrier result and PopScope | `compact-600`, `initial-first-row`, `remove-index-plus-one`, `last-item-pop-false`, `last-item-pop-null`, `barrier-pop-true`, `editor-cancel`, `editor-delete-write`, `editor-failed-update`, `editor-back-result` |
| Manage | B: loading/empty/list, Center static, subtitle labels, source-only refresh, single active refresh and spinner, success/reload/Close result, failure red snackbar, delete cancel/confirm, focus chain and 56-px offsets | `manage-scroll-48`, `refresh-concurrency`, `subtitle-trakt-mdb`, `manage-delete-cancel`, `manage-refresh-result`, `manage-refresh-error` |
| File/static imports | B: picker cancel/empty, exact cap acceptance and +1 rejection, null bytes, error/success/exception, case-insensitive suffix, duration/color, six dialog entry points and bool conversion including repo | `file-cap-off-by-one`, `json-suffix-case`, `snackbar-durations`, `file-read-error`; URL/JSON/Trakt/MDBList success/cancel proofs below |
| URL | B: empty/invalid/importer/HTTP/exception errors, trimmed single GET, forwarded name, submit, disabled Import, 15-s timeout, button/field D-pad, TV shell Back vs editing Back vs non-TV | `url-timeout-30`, `url-http-message`, `back-browserback`, `url-name-forward`, `url-submit` |
| JSON | B: empty/importer error, forwarded name/split persistence/true, Up start/Down end/select empty/Esc, button maps | `json-up-start-import`, `json-empty`, `json-save-result` |
| Trakt picker | B: auth message, direct name/meta and duplicate suffixes, ordered fetch, custom/liked metadata and routing, split and single saves, missing owner, empty/no-IMDb, empty directories and source labels | `trakt-direct-name`, `trakt-list-meta`, `trakt-auth`, `trakt-movies-shows-order`, `trakt-split-type`, `trakt-missing-owner`, `trakt-empty`, `trakt-no-imdb`, `trakt-duplicate`, `trakt-source-label`, `trakt-api-value` |
| MDBList picker | B: auth, mine/liked/top routing, duplicate names/suffixes, load failures/partial/empty, metadata owner/id, split/single save and true result | `mdb-auth`, `mdb-meta`, `mdb-duplicate`, `mdb-split-type`, `mdb-single-type`, `mdb-dialog-incomplete`, `mdb-empty` |
| Diagnostics/resource ordering | S: exact debug log literals, debug labels, and disposal order (no existing callback exposing disposal sequence) | `trakt-log`, `trakt-log-spaces`, `focus-debug-label`, `dispose-order`; checker negatives also reject label/timeout/dispose edits |
| Disabled MDBList branch | S: `kMdblistEnabled` is a compile-time true constant, no existing toggle seam | `mdb-disabled-error` |
| Service catch branches | S: non-strict Trakt/MDBList services convert transport/parse errors to empty results; no production singleton-injection or storage-failure seam exposing arbitrary throws into these dialog catches | `trakt-fetch-catch`, `trakt-direct-catch`, `mdb-fetch-catch`, `mdb-import-catch`; exact source assertions count all catch text occurrences |
| Theme/shape | S construction guard plus existing shape suite: four bare radii / six app shape calls in this slice; layouts covered B | `shape-radius`, unchanged whole-declaration comparison, exact arguments and exact 488 floor in source guard, and existing shape tests; no goldens by plan |

The equivalent `_changed` last-item mutation is intentionally absent: assignment
precedes the literal `pop(true)`. Separate false/null pop mutants assert both
actual storage deletion and returned true. For retained service compatibility,
source guards supplement B checks (200-ms ensureVisible/animate, labels, timeout,
barrier/PopScope). They are never used to count a B kill.

The not-found editor path does not call `_rebuildNavigation`; the test uses
system Back via PopScope for that path. Found-channel Escape/goBack is exercised
through the installed key handlers. This is preserved, not fixed.

## Shape, theme, CI and documentation inventory

Original shape budget is 4 in `kShapeResidue`; exactly six `app.shape.*` calls
are present. URL/JSON/editor each retain two and enter `kShapeResidue` on
creation. Manage/Trakt/MDBList each have one bare radius and no token calls;
those and the zero-budget data files enter `kExtractedShapeResidue`. Original
budget becomes 4 → 1 → 0 then its facade entry moves to extracted residue.
The existing floor is exactly 488; each checkpoint must retain it and the
aggregate slice of four bare radii. Step 0 activates no destination entries.

`theme_surface_manifest.txt` does not cover this original widgets directory or
the planned feature; no theme registration is added. `text_white_sweep.in_scope`
returns false for every planned path because `stremio_tv` is a substring of
`stremio_tv_catalogs`. The docs path at `docs/stremio/building-local-catalogs.md:7`
changes only in Step 4. All eight new test files are appended to
`dev/tool/ci_behavior_tests.txt`; no known-failure or analyzer allowlist changes.
Remote CI and device/emulator/build/install checks are outside Step 0 and are
not run. Existing tests/checks are unchanged, except the explicit opt-in
extension support in the shared checker.

## Step 0b review coverage on ORIGINAL

`dev/tool/stremio_tv_catalogs_review_mutations.json` adds 40 B cases and one
S case without replacing any Step 0 assertion or mutation. The 25 additional
`review ` test identities remain in the existing eight CI-listed test files.
The original manifest reader and harness remain frozen.

| Review boundary | Classification | New mutants |
| --- | --- | ---: |
| Four alias targets and true/false/null mappings; repo delegation and mapping; centered manage dialog | B: actual dialog widgets, Navigator results and geometry | 11 |
| Editor Close/row D-pad chain and consumed keys; selected confirm; changed barrier and system Back; exact ordered persistence and last-row focus | B: real key events, confirm text, storage and route results | 8 |
| Manage selected catalog and delete flag; Close true; barrier/system Back null after delete (Found-not-fixed #1) | B: exact remaining catalogs and route results | 5 |
| URL Cancel Up, both left/right transitions, Select/space null dismissal and queued loading suppression | B: focus, route payload and recorded HTTP request count | 7 |
| JSON Down/activate at nonempty end and Escape | B: focus targets | 3 |
| Trakt custom/liked directory calls, custom versus owner subtitle, direct-source error reset | B: distinct HTTP endpoints/payloads and visible state | 3 |
| MDBList mine/liked/top loaders and category-specific empty text | B: distinct HTTP endpoints/payloads and visible text | 3 |
| Trakt `_onSourceChanged` list reset | S: direct-source UI hides `_lists`; picker transitions synchronously reset it again in `_fetchLists` before displaying/loading. Dropping this assignment alone is behavior-equivalent through existing public seams. | 1 |

The editor key test records results from the existing public FocusNode handlers
while dispatching actual key events; framework traversal cannot mask removal
of the custom arrowUp handler. The URL test queues two Select events before
the disabled button rebuilds, so dropping `_loading` exposes a second request.
Repo delegation and `Center` are observable and require no S exception.
All B cases run without the source-guard suite; S runs separately.

Evidence is owned by Git's common directory at
`$(git rev-parse --path-format=absolute --git-common-dir)/refactor-evidence/stremio_tv_catalogs/`.
The evidence wrapper resolves that path before switching its suite root to an
owned scratch copy. No evidence belongs in the worktree, and the Step 0
`.gitignore` addition is reverted to its pre-Step-0 bytes.
