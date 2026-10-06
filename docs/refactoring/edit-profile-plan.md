# Edit profile screen refactor — plan

Written 2026-10-06 on `refactor/edit-profile` (cut from `refactor/codebase` at
`0cb50df7`). Follow [AGENTS.md](../../AGENTS.md). Templates, in order of
relevance: [debrify-tv-plan.md](debrify-tv-plan.md) (owner records, the
occurrence-level field-binding guard, live getters, frozen section map, step
0/0b split, Progress and round resolutions), [catalog-detail-plan.md](catalog-detail-plan.md)
(per-field widget closures, a lazy `late` kept on the State behind a deps
getter/setter, source reader with reversal, evidence classes R/O/S, goldens)
and [spotlight-board-plan.md](spotlight-board-plan.md) (the gate-1
renamed-field-capture lesson). This plan reuses their technique, checker,
tooling, staging and gates and states only what differs.

## Execution model

- Execution runs in the worktree `../debrify-wt/edit-profile` on branch
  `refactor/edit-profile`. Record the **execution base SHA** (R) in Progress at
  step 0 and name it in every proof. `flutter pub get` first; the lockfile must
  not change. Flutter 3.44.8 / Dart 3.12.2.
- Commit after every step; never push, merge or switch branches. Gate commits
  contain `gate`.
- **Four other refactors run in parallel** on sibling branches (Stremio TV
  screen, its local-catalogs dialog and tuner, settings widgets). Shared-file
  edits (architecture guard, shape test, theme manifest, CI lists, known
  failures, `checks.yml`, size baseline, analyzer allowlist, shared checker
  tooling) stay **additive and keyed by `edit_profile`**; the integrator
  union-merges them. In `checks.yml` paths go before `| tee`, never after it.
  Expect high machine load: gates run serially; load-sensitive flakes (WebDAV
  shard, the 180 ms PIN settle) are rerun in isolation with a NOTE, never
  allowlisted.
- **Evidence** goes only to `<git-common-dir>/refactor-evidence/edit_profile/`.
- **Isolation:** every manifest, format-proof and checker command passes its own
  `--parser-package` under the ignored `.dart_tool/edit_profile_parser/`
  (delete any copied `*.dill`); original-code proofs use a detached worktree
  under `.dart_tool/edit_profile_original/`.
- **No device or emulator runs.** Device-only behaviour goes to the
  End-of-series device checklist below.

## Goal

`lib/screens/profiles/edit_profile_screen.dart` is **2,764 lines** (31 imports;
one private top-level enum; 9 classes: the public widget, its State, the
immutable save snapshot, four private TV widgets and two of their States). It is
the profile create/edit form for phone and TV: avatar (built-in art, legacy
icons, picked image/GIF), name, role, the TV Pages policy editor, PIN and
auto-lock, engine and connection access, ownership transfer, admin PIN reset
and diagnostics. Split it into **`lib/features/edit_profile/`**, **moving code
verbatim**; widget tree, keys, focus nodes, build order, lifecycle, and every
registry/PIN/grant/engine write and its ordering are unchanged.

**Name and facade.** `edit_profile` matches the file name and the TV key prefix
`tv-profile-*` without colliding with `lib/screens/profiles/` (manage profiles,
setup flow, gate) or `lib/services/profiles/`. `EditProfileScreen` stays at
`lib/screens/profiles/edit_profile_screen.dart`: three production callers
import it (below) and `profile_source_guard_test` reads that path.

**Risk profile.** No playback. The risk is **profile ownership**: every write
must still target the originating profile under the originating managing
admin's authorization, with the same validate/refresh ordering. Core profile
services (`profile_registry.dart`, `profile_pin_service.dart`,
`profile_creation_service.dart`, `profile_authorization.dart`,
`profile_avatar_*`, `connection_resource_service.dart`,
`profile_engine_assignment_service.dart`, `profile_runtime.dart`,
`main_page_bridge.dart`) **must not change**.

**Architectural status:** a bounded legacy-extraction stage. Exceptions and exits:
- **State-driven sections instead of Riverpod.** Exit: a profile-editor
  notifier keyed by target profile and route instance, in a later change.
- **A `legacy_edit_profile/` bridge** calling profile services, the registry,
  `FilePicker`, `dart:io` and `Clipboard` directly. Registered as the feature's
  only service-importing folder. Exit: a profile-editing repository contract
  (load options, save, grant, transfer, PIN reset), after which the folder
  dissolves.
- **Unchanged legacy text.** Exit: the app-wide localization migration.
- **Duplicated focus surfaces** (`_TvActionSurface` and friends). Exit: a shared
  TV focus primitive under `lib/ui/core/` once reuse is demonstrated.

## Public surface (unchanged)

`EditProfileScreen` (lines 35–88, the class doc through `createState`): five
fields (`registry`, `pins`, `authorization`, `profile`, `@visibleForTesting
setupOptionsLoader`), the const constructor, `@visibleForTesting static const
bool showFeaturePolicyControls = false`, `@visibleForTesting static ProfilePolicy
policyFor(...)` with its doc, and `createState`. These lines stay
**byte-identical** in the facade, pinned by
`dev/tool/edit_profile_public_surface.txt`.

- **Production callers (3), unchanged:** `manage_profiles_screen.dart:119`,
  `profile_setup_flow.dart:439`, `settings/profiles_settings_page.dart:162`.
- **Tests:** `test/profiles/edit_profile_screen_test.dart` (22 cases: `policyFor`
  units, rendering, TV rail/pane focus at several sizes; **not in CI**);
  `test/profiles/profile_source_guard_test.dart:113–151` (CI; reads the file
  text, see Step 0.8); `profile_setup_flow_test.dart` (comment reference only).

## What it contains (lines at `0cb50df7`; after step 0 the manifest is authoritative)

| Lines | Area | Notes |
| --- | --- | --- |
| 1–31 | 31 imports | |
| 33 | `enum _TvProfileSection { profile, pages, access, lock, data }` | `.name` feeds debug labels and keys; values index the rail. |
| 35–88 | `EditProfileScreen` | Stays in the facade. |
| 90–325 | `_EnsureVisibleOnFocus`, `_TvReadOnlyScrollAnchor`(+State), `_TvActionSurface`(+State), `_TvAutoLockField` | Pure widgets (no service import); `_TvAutoLockField` uses `_TvActionSurface`, `showDialog`, `TvHeldKeyGuard`. |
| 327–361 | `_ProfileEditSnapshot` (doc, 13 finals) | Pure model; built in `_save`, read by `_applyResourceGrants`. |
| 363–410 | State fields | 26 fields; four eager initializers (`_pin`, `_tvContentFocus`, `_tvBackFocus`, the three collections); **`late ProfileAuthorizationContext _authorization = widget.authorization`** is lazy and reads `widget`. Interleaved docs/comments (374, 377–379, 391–394, 398–400). |
| 412–438, 566–578 | `initState`, `dispose` | Stay verbatim in the State. |
| 440–510 | `_loadSetupOptions`, `_loadResources` | Authorization validate → loader or registry+engine service → grant seeding → `_validateManagingAdmin` → `mounted` → one `setState`. |
| 512–564 | `_transferOwnership` | Builder `context` shadows the State's. |
| 580–670 | `_setRole`, `_pickAvatarImage`, `_readPickedBytes` | |
| 672–1099 | `_showRecoveryCode`, `_save` (270 lines), `_restoreTvSaveFocus`, `_applyResourceGrants`, `_applyEngineAssignments`, `_defaultResourcePermissions`, `_validateManagingAdmin`, `_refreshSameManagingAdmin` | The profile-ownership core. |
| 1101–1157 | `_selectResource`, `_deselectResource`, `_editableIn`, `_showDiagnostics` | |
| 1159–1330 | `// ── build ──` banner, `_sectionLabel`, `build` (TV dispatch at 1174, then the phone form) | |
| 1332–1670 | `_buildTvEditor`, `_buildTvSectionRail`, TV key/focus navigation (8 members incl. the `_tvContentStops` getter) | |
| 1672–2288 | TV panes: Pages, Profile (+preview, avatar tile, role cards), Lock, Access, Data, `_tvPanel` | |
| 2290–2522 | `_removePinAsAdmin(Locally)`, phone avatar section, `_artTile`, phone role cards | |
| 2524–2763 | Engine group, `_tvAccessFocusRow`, `static const _accessGroups` (doc), connection groups/rows (trailing comment block), `_groupHeader`, `static _featureLabel` | |

No member exceeds 500 lines. The file is formatter-idempotent at R and `flutter
analyze` reports no issues for it (re-measure at step 0).

## Contracts that must not change

1. **Public surface** as above; all 3 callers and the tests compile unchanged.
2. **Lifecycle.**
   - Eager construction order: `_pin`, `_tvContentFocus` (debug label, `canRequestFocus:
     false`, `skipTraversal: true`), `_tvBackFocus`, `_selectedResources`,
     `_selectedEngines`, `_resourcePermissions` — the owners are built eagerly
     as one State field initializer in that relative order.
   - `initState`: `super.initState()` first; the six tab focus nodes (five
     sections then Save, labels unchanged); `_name` from `profile?.name`;
     `_role`; `_features` from the stored policy or role defaults (the
     source-guarded expression); the two seeds; lock, inactivity, avatar key
     (child → `'child'`, else `'person'`); `_loadSetupOptions()` unawaited, last.
   - `dispose`: tab nodes in order, `_tvContentFocus`, `_tvBackFocus`,
     `_name`, `_pin..clear()..dispose()`, `super.dispose()` last.
   - **`_authorization` stays on the State** as the lazy `late` with its
     initializer, exactly as declared. Sections read and assign it only through
     a deps getter/setter pair (`_deps.authorization`), the catalog
     `hasBoundSource` precedent, so its first evaluation stays at the original
     first read (`_loadSetupOptions`, from `initState`).
3. **Profile ownership and authorization** (the main risk).
   - The target is fixed per operation: `staged.id` (create), `existing.id` /
     `savedProfileId` (edit), `widget.profile!.id` (PIN reset), `target.id`
     (transfer). No write resolves the active profile implicitly.
   - `operationActor` is read from `_authorization` **at its original site**:
     in `_save` after the optional `ProfileAvatarIngest.prepare` await (source
     777 then 783), in `_transferOwnership` before its first validation, in
     `_removePinAsAdminLocally` first. It is never hoisted.
   - Validate/refresh sequences are preserved exactly as written, not
     normalised: `_save` validates once before the first write; **create**
     runs PIN set → `updateProfile` → refresh (no refresh between PIN and
     update) → grants (refresh after each grant/revoke) → engines →
     `completeStaged`; **edit** runs publish → refresh → optional PIN →
     refresh → grants → engines; transfer validates before the dialog and
     again before the write, then refreshes; PIN reset validates, removes,
     refreshes. `_refreshSameManagingAdmin` throws `StateError('Managing
     profile session changed')` when the active profile changed;
     `_validateManagingAdmin` throws for a non-admin or a missing
     `manageProfiles`. No refresh is added or removed.
   - `_authorization` is assigned only at the original sites (after a
     successful save, before the `mounted` check; after transfer; after PIN
     reset).
   - `MainPageBridge.reloadProfilePolicy?.call()` only when
     `ProfileRuntime.isProfileCommitted` and the edited profile is the captured
     active profile.
4. **Save.** Guards in order (saving/empty name; options loading or load error
   → snackbar with `_setupLoadError ?? 'Profile options are still loading'`;
   PIN regex `^\d{4,8}$`). Pair-follow rule (`recordings` follows `downloads`,
   `remoteTransfer` follows `remoteControl`, only when moved from the seeds),
   role-ceiling clamp, then the **immutable snapshot built synchronously before
   `setState(() => _saving = true)`**. The snapshot holds exactly its 13
   fields; every other read stays live at its original site, including
   `_policyTouched` and `widget.profile` inside the `policyFor` call after the
   validation await (source 793–794), `widget.profile` in the branch and tail,
   and `_authorization`. Nothing is added to the snapshot and no read is
   hoisted. `policyFor` with `controlsShown = showFeaturePolicyControls ||
   _policyTouched || role changed on edit`.
   - **Create:** `createStaged(…, avatarKey: snapshot.avatarKey)` →
     `ProfileAvatarMutation.runExclusive(staged.id, …)`: `begin` → candidate
     write (picked image) → PIN (`setPinAsAdmin`, recovery code kept) →
     `updateProfile` (avatar, lock, timeout or clear, acting identity) → refresh
     → grants → engines → `completeStaged` → `stagedPublished = true` → avatar
     `commit` + `complete` with errors swallowed. On error: re-read the
     profile; roll back (`rollbackStaged` + mutation `complete`) only when not
     published and not active; rethrow with the original stack trace.
   - **Edit:** `ProfileAvatarIngest.publish(persist:, wasPersisted:)` with the
     six-field comparison → refresh → optional PIN + refresh → grants →
     engines.
   - **Success tail, in order:** `_authorization = operationActor`; `mounted`;
     avatar key, features, seeds, `_policyTouched = false`, pending bytes
     cleared, PIN cleared (no `setState`); policy reload rule; recovery dialog
     (barrier not dismissible) then `mounted`; `Navigator.pop(true)`.
   - **Failure:** `ProfileAvatarRejected` → its message; anything else →
     `'Could not save this profile'`; both reset `_saving` in `setState`, call
     `_restoreTvSaveFocus` (TV only, post-frame, `mounted && !_saving &&
     isCurrent`, focuses the rail Save node), then show the snackbar.
5. **Grants and engines.** `_applyResourceGrants` per resource in snapshot
   order: existing grant, `selected`, desired = stored mask or
   `_defaultResourcePermissions(role, features)`, singleton binding check;
   grant when selected and (missing, mask differs or binding mismatched);
   revoke when deselected, granted and not owned by the target; refresh after
   each write; returns the latest actor. `_applyEngineAssignments` →
   `ProfileEngineAssignmentService.apply`. Selection rules: `_selectResource`
   deselects singleton-slot rivals (and drops their masks) and seeds the mask
   with `putIfAbsent`; `_deselectResource` keeps the mask; owned rows are not
   editable; load-time seeding adds `use` to each stored grant; create selects
   every engine, edit selects the assigned ones.
6. **Avatar picking.** `FileType.any`, `withData: false`, the 12 MB checks
   (declared size, inline bytes, streamed length), `ProfileAvatarIngest.prepare`,
   the `!mounted || _saving` guard before publishing the pending bytes, the
   three snackbars, and `CacheScratchCleanup.releasePickerCopy` in `finally`.
7. **PIN.** Validation message; recovery dialog text and `I saved it`; admin
   reset (`removePinAsAdmin` under the validated actor, refresh, two
   snackbars).
8. **TV focus and navigation.** Rail: five sections then Save, autofocus index
   0, keys `tv-profile-tab-<name>` / `tv-profile-save`, UP from index 0 to the
   Back node when the route can pop, synchronous section select on UP/DOWN,
   RIGHT/OK enters the pane; `_tvFocusRequest` generation and the post-frame
   checks in `_focusTvContent`; `_moveTvContent` row/column geometry and the
   LEFT-edge return to the rail; text-field edge callbacks; `TvHeldKeyGuard`
   around panes; read-only Access rows keep a focus stop. Keys
   `tv-profile-name`, `tv-profile-pin`, `tv-profile-auto-lock`,
   `tv-profile-avatar-*`, `tv-profile-role-*`, `tv-pages-*`,
   `tv-profile-engine-*`, `tv-profile-connection-*`,
   `tv-profile-name-preview`.
9. **Layouts.** Phone `ListView` section order (Avatar, Identity, Role,
   [hidden feature controls], Lock, Access, Data); TV rail 200 wide with the
   pane switch; role cards horizontal ≥ 560 (phone) / stacked < 620 (TV);
   preview compact < 420; access group order and the trailing "Other
   connections" bucket; Reddit rows skipped.
10. **Save locking.** `PopScope(canPop: !_saving)`, `Focus(descendantsAreFocusable:
    !_saving, descendantsAreTraversable: !_saving)`, `AbsorbPointer(absorbing:
    _saving)` on both layouts; `SAVING…` rail label; disabled buttons.

## Destination layout

All under `lib/features/edit_profile/`; every file ≤ 500 formatted lines (no
size exception is authorized). Estimates include imports, headers and
receiver-induced wraps; the creation commit measures each file.

**Outside the bridge (service-free):**

| File | Contents | Est. |
| --- | --- | --- |
| `models/edit_profile_tv_section.dart` | `enum _TvProfileSection` verbatim + `typedef EditProfileTvSection = _TvProfileSection;` | 6 |
| `models/edit_profile_snapshot.dart` | `_ProfileEditSnapshot` verbatim (doc kept) + `typedef EditProfileSnapshot = _ProfileEditSnapshot;` | 45 |
| `presentation/edit_profile_tv_surfaces.dart` | `_EnsureVisibleOnFocus`, `_TvReadOnlyScrollAnchor`(+State), `_TvActionSurface`(+State), `_TvAutoLockField` verbatim, one typedef each for the four widgets | 250 |

Private declarations keep their runtime types and keyless private
constructors (catalog/Debrify TV precedent). The rename probe measures any
`unused_element_parameter` or `library_private_types_in_public_api` identity
caused by typedef construction from another library; if one appears, the
Debrify TV frozen constructor-forwarder pattern is used and frozen in
`edit_profile_scaffolding.json` — never a constructor, default, key or `const`
change and never a suppression.

**`presentation/legacy_edit_profile/` (the bridge; exact path in the guard):**

| File | Section key / class | Contents | Est. |
| --- | --- | --- | --- |
| `edit_profile_dependencies.dart` | — `EditProfileDependencies` | live `context()`, `mounted()`, `setState`; widget-field closures `registry()`, `pins()`, `profile()`, `setupOptionsLoader()`; `policyFor` (the static tear-off) and a `showFeaturePolicyControls` getter; the `authorization` getter/setter pair forwarding to the State's lazy field; `owners`, `late final sections` | 70 |
| `edit_profile_owners.dart` | — `EditProfileOwners` | `form`, `tv`, `access` records, eager, constructed in that order | 20 |
| `edit_profile_form_state.dart` | `_owners.form` | `name` (`late final`), `pin`, `role`, `features`, `saving`, `copyDefaults`, `lockOnResume`, `inactivityMinutes`, `avatarKey`, `policyTouched` (doc), `seedDownloads`/`seedRemote` (comment), `pendingAvatarBytes` (doc) | 45 |
| `edit_profile_tv_focus_state.dart` | `_owners.tv` | `tvSection`, `tvTabFocusNodes` (comment), `tvContentFocus`, `tvBackFocus`, `tvLastContentFocus`, `tvFocusRequest` | 25 |
| `edit_profile_access_state.dart` | `_owners.access` | `resources`, `engines`, `selectedResources`, `selectedEngines`, `resourcePermissions`, `setupLoadError` | 20 |
| `edit_profile_sections.dart` | — `EditProfileSections` | constructs every section once, inert constructors | 45 |
| `edit_profile_setup_options.dart` | `setup` / `EditProfileSetupOptions` | `_loadSetupOptions`, `_loadResources` | 90 |
| `edit_profile_admin_guard.dart` | `admin` / `EditProfileAdminGuard` | `_validateManagingAdmin`, `_refreshSameManagingAdmin` | 45 |
| `edit_profile_admin_actions.dart` | `adminActions` / `EditProfileAdminActions` | `_transferOwnership`, `_removePinAsAdmin`, `_removePinAsAdminLocally`, `_showDiagnostics` | 135 |
| `edit_profile_avatar_picker.dart` | `avatar` / `EditProfileAvatarPicker` | `_pickAvatarImage`, `_readPickedBytes` | 90 |
| `edit_profile_save.dart` | `save` / `EditProfileSave` | `_showRecoveryCode`, `_save` | 355 |
| `edit_profile_grants.dart` | `grants` / `EditProfileGrants` | `_applyResourceGrants`, `_applyEngineAssignments` | 90 |
| `edit_profile_selection.dart` | `selection` / `EditProfileSelection` | `_setRole`, `_defaultResourcePermissions`, `_selectResource`, `_deselectResource`, `_editableIn` | 85 |
| `edit_profile_tv_navigation.dart` | `tvNav` / `EditProfileTvNavigation` | `_restoreTvSaveFocus`, `_tvDirection`, `_handleTvRailKey`, `_selectTvSection`, `_tvContentStops`, `_requestTvContentFocus`, `_focusTvContent`, `_returnToTvRail`, `_moveTvContent` | 170 |
| `edit_profile_phone_form.dart` | `phone` / `EditProfilePhoneForm` | the `// ── build ──` banner, `_sectionLabel`, the `build` body as `build(BuildContext context)` (TV dispatch first, verbatim), `static _featureLabel` | 200 |
| `edit_profile_phone_parts.dart` | `phoneParts` / `EditProfilePhoneParts` | `_buildAvatarSection`, `_artTile`, `_buildRoleCards`, `_roleCard` | 225 |
| `edit_profile_tv_editor.dart` | `tvEditor` / `EditProfileTvEditor` | `_buildTvEditor`, `_buildTvSectionRail` | 220 |
| `edit_profile_tv_profile_pane.dart` | `tvProfile` / `EditProfileTvProfilePane` | `_buildTvProfileSection`, `_buildTvProfilePreview`, `_tvAvatarTile`, `_buildTvRoleCards` | 295 |
| `edit_profile_tv_panes.dart` | `tvPanes` / `EditProfileTvPanes` | `_buildTvPagesSection`, `_buildTvLockSection`, `_buildTvAccessSection`, `_buildTvDataSection`, `_tvPanel` | 365 |
| `edit_profile_access_rows.dart` | `access` / `EditProfileAccessRows` | `_buildEngineGroup`, `_tvAccessFocusRow`, `static const _accessGroups` (doc), `_buildConnectionGroups`, `_connectionGroup`, `_groupHeader`, `_connectionRow` | 265 |

The key/class/file triples above are the **frozen section map**, used
identically by contracts, manifest, composition and callback fixtures; a change
is a plan amendment. Cross-file privates become manifest-listed public names
(`_save` → `save`, …); members called only inside their own file keep their
private names. The original's interleaved field docs/comments travel with
their fields.

**Widget and static references.** Sections never see `EditProfileScreen` (no
facade back-import): `widget.registry` → `_deps.registry()`, `widget.pins` →
`_deps.pins()`, `widget.profile` → `_deps.profile()`,
`widget.setupOptionsLoader` → `_deps.setupOptionsLoader()` (so
`widget.setupOptionsLoader!()` becomes `_deps.setupOptionsLoader()!()`), each
evaluated at the original site. `EditProfileScreen.policyFor(` →
`_deps.policyFor(` (the facade wires the static tear-off; callers always pass
`controlsShown`) and `EditProfileScreen.showFeaturePolicyControls` →
`_deps.showFeaturePolicyControls` (a getter returning the static const). All
are registered receiver substitutions; the reader reverses them.

**The facade** (`lib/screens/profiles/edit_profile_screen.dart`) holds sorted
imports, `EditProfileScreen` byte-identical, and `_EditProfileScreenState` with
the eager `final EditProfileOwners _owners = EditProfileOwners();`, the lazy
`late ProfileAuthorizationContext _authorization = widget.authorization;`
unchanged, a nullable cached composition (`EditProfileSections? _composition`
plus a getter building it once; never `late`, never per build), the verbatim
lifecycle with receivers and `Widget build(BuildContext context) =>
_sections.phone.build(context);`. Estimate 140–170 lines. **Cap:** the measured
complete facade, target ≤ 200, at most 250 (above 250 is a plan failure to
report). `TEMP(edit_profile)` rejection from step 6.

**Guard rules** (step 1, `check_search_architecture.py`): `edit_profile` in
`FEATURES`; `EDIT_PROFILE_FACADE`, `EDIT_PROFILE_BRIDGE`,
`EDIT_PROFILE_COMPLETE = False`; service/`dart:io`/`file_picker` imports only
inside the exact bridge (the Spotlight rule; `presentation/*.dart` and
`models/` import no `lib/services/`); no `lib/features/` file imports the
facade; no import between `edit_profile` and any other feature except
`<other>/models/` (expected: none); 500-line caps; completion `main()` scan,
facade cap and `TEMP` rejection at step 6 (facade in `COMPOSITION_ROOTS` with a
comment, as Debrify TV). Real-checker negatives at step 6: facade missing,
facade at cap + 1, `TEMP(edit_profile)` in facade and in a feature file, a
service import in `presentation/edit_profile_tv_surfaces.dart`, a facade
back-import, a feature file at 501 lines; the unmodified tree passes.

## Technique

As in the Debrify TV plan, plus:

1. **Original R without a format commit.** The file is formatter-idempotent at
   R; record `format-idempotence.json`. If the base moved and it no longer is,
   fall back to the format-only commit precedent.
   **(b) Characterization checkpoint** (`test(edit-profile): step 0
   original-code characterization checkpoint`): `lib/` equal to R
   (`git rev-parse <b>:lib` = `<R>:lib`, plus `pubspec.yaml`/`pubspec.lock`).
   No production seam; if one proves unavoidable, stop and report.
2. **Strict-lint baseline and rename probe** at R in a scratch copy under the
   features analysis config, recorded by identity (rule, enclosing member,
   message); the probe applies the manifest's renames/receivers to a compiling
   copy and inventories every change (`use_build_context_synchronously` around
   `_deps.mounted()`, typedef-construction warnings). Baseline and probe
   combine by maximum per identity. Any surviving warning gets its
   `analyzer_allowlist.txt` entry by destination path in the commit creating
   its file. No `const`, key, constructor or suppression change.
3. **Live getters and setState.** Sections reach `context`, `mounted`,
   `setState` and the widget fields only through `_deps`, at the original
   evaluation site; nothing is hoisted or cached. **Lexical scopes stay
   lexical**: the `context` parameters of `build` and `_buildTvEditor`, the
   `ProfileAuthorizationContext context` parameter of `_validateManagingAdmin`
   (never the State-context getter), builder `context` parameters (`_transferOwnership`'s dialog
   builder, the LayoutBuilders in the rail, preview, TV role cards and phone
   role cards), `dialogContext`, and every local function that reads the
   State's `context` (`railItem`, `railLabel`, `group`, `tile`, `card`) are
   enumerated in the dependency report with their binding; the
   `lexical_state_setters`/context guard covers both directions (a builder
   `context` turned into `_deps.context()` and a State `context` turned into a
   builder parameter).
4. **Field ownership and the field-binding guard.** All 25 non-`_authorization`
   fields move at step 2 into the three records, renamed by dropping the
   underscore; **every moved field reference is receiver-qualified**
   (`_owners.form.role`). Enable the existing opt-in `occurrence_field_bindings`
   check for this config. It is **not** usable as is (round 1: it hard-codes
   `_DebrifyTVScreenState` at `occurrence_field_bindings.py:52/83`, and a
   scratch probe of these rewrites failed alignment, 10 ≠ 11), so step 0
   extends it, config-scoped and additive:
   - the State class(es) come from config (`state_classes`), Debrify TV's
     config naming `_DebrifyTVScreenState` so its behaviour and self-tests are
     unchanged;
   - a config list of **registered occurrence substitutions**, each with its
     expected role change and qualifier chain: `widget.<f>` (selector, read)
     → `_deps.<f>()` (selector, invocation) for `registry`, `pins`,
     `profile`, `setupOptionsLoader` (including `widget.setupOptionsLoader!()`
     → `_deps.setupOptionsLoader()!()` and nested chains such as
     `widget.profile?.id`, `widget.registry.getGrant`);
     `EditProfileScreen.policyFor` → `_deps.policyFor` and
     `EditProfileScreen.showFeaturePolicyControls` →
     `_deps.showFeaturePolicyControls`; the retained State field
     `_authorization` (lexical, unbound) → `_deps.authorization` (selector)
     for reads, writes and nested chains (`_authorization.validate(…)`,
     `_authorization.profileId`); plus the existing `context`/`mounted`/
     `setState` live-getter forms;
   - any other inserted, removed or reordered occurrence still fails, and
     mandatory qualification of moved fields is kept.
   Positives and negatives for every substitution kind (a substitution
   applied at the wrong occurrence, a `widget.profile` read replaced by
   `_deps.profile` without invocation, an `_authorization` write turned into
   a section field) run **through both the checker and the reader at step 0**,
   and the step-0b compiling-composition probe applies the full rewrite set
   to a compiling copy and passes the real checker before step 2.
   Hazards (dependency report lists all): `_setRole(role)`,
   `_defaultResourcePermissions(role, [features])`, `_roleCard(role, …)` and the
   role-card loops (`role` vs `_role`); locals `resources`, `engines`,
   `selectedResources`, `resourcePermissions` in `_loadSetupOptions` assigned
   into same-named fields inside `setState`; the same `resources` local/field
   assignment in `_loadResources` (500–503); `resources` in
   `_applyResourceGrants`/`_buildConnectionGroups`; `engines` in
   `_buildEngineGroup`; `section` in `_selectTvSection`/`_focusTvContent` vs
   `_tvSection`; `selected` locals vs `_selectedResources`/`_selectedEngines`
   (no collision after renaming, but listed). Negatives (real config, through
   checker and reader): `_owners.form.role = role` in `_setRole` turned into a
   bare `role`; `_owners.access.resources = resources` turned into
   `resources = resources`; a balanced field/local swap in `_loadSetupOptions`;
   `_defaultResourcePermissions`' `features ?? _features` with the field read
   replaced by the parameter; a bare record member inside a section and inside
   a record. Positives cover every hazard. The guard runs from step 2.
5. **`_authorization` deps pair.** `_deps.authorization` (get) and
   `_deps.authorization = …` (set) are registered occurrence substitutions for
   `_authorization` (Technique 4); the checker rejects a cached copy, a read
   hoisted above its original site, and a write moved across an `await`.
   Composition negatives (S): the pair wired to a separate eager field instead
   of the State's lazy `late`; a section field caching the actor; the facade
   declaration changed from `late … = widget.authorization`.
6. **Receivers and composition.** Sections hold `final EditProfileDependencies
   _deps;` with `_owners`/`_sections` getters; cross-section calls are
   `_sections.<key>.<member>` (registered `receiver_paths`/`receiver_owners`);
   `EditProfileSections` constructs every section once, in a fixed order,
   storing only `_deps`.
7. **Callback identity** (receiver path + member, wrapper and same-class
   receiver-swap negatives) at: both Save `onPressed` (`_saving ? null : _save`,
   phone AppBar and TV rail); both `_pickAvatarImage`; both
   `_removePinAsAdmin`; both Retry `_loadSetupOptions`; both
   `_showDiagnostics`; both `onLeftArrow: _returnToTvRail`;
   `railItem`'s `onKeyEvent` closure (`_handleTvRailKey(index, event)`);
   `editable.forEach(_selectResource)` / `forEach(_deselectResource)`;
   `setState(_selectedEngines.clear)`; `onPressed: () =>
   _transferOwnership(resource)`; `_TvAutoLockField.onChanged` and the
   `SwitchListTile`/`Dropdown` closures. Negatives at each: a wrapper closure,
   a receiver swap to another section, a member swap
   (`_removePinAsAdmin` ↔ `_removePinAsAdminLocally`, `_selectResource` ↔
   `_deselectResource`), a cached tear-off field.
8. **Verbatim comments.** Never reword, move or drop one, including the
   `// ── build ──` banner (travels with `_sectionLabel`), the in-list comment
   block in `_connectionRow`, and field docs.
9. **Shape and theme.** The file is in neither shape map nor the theme
   manifest today; step 0 measures its bare radii with the shape test's regex
   (grep finds 14 `circular(`). From step 1 register the facade and every
   destination in `kExtractedShapeResidue` with its exact count (zero-budget
   files included), reconciling to the measured total at every step; the
   488-token `kShapeResidue` floor is untouched. Theme: verify the file is
   outside every measured surface (no manifest change) or, if a surface
   reaches it, add explicit per-directory patterns and keep its site count.
   Light-ink: verify not `PRIMARY`.

## Steps

| # | Work | Contracts |
| --- | --- | --- |
| 0 | Baseline `edit_profile/base`; format idempotence; strict and rename probes; dependency report (`docs/refactoring/edit-profile-deps.md`); manifest, checker config, scaffolding, public-surface file; harness and characterization tests; source reader and the source-guard switch; macOS goldens (two reversed-order captures); CI list; Linux capture script; checkpoint (b) | Nothing moves |
| 0b | Independent review (Claude) closure; original-only mutation proofs for every case; compiling-composition probe with the real checker and facade measurement; `base2` at (b) | Nothing moves |
| L | **Before step 2:** Linux originals captured by Claude in Docker, hash-verified, committed separately; Linux golden test strict | Goldens |
| 1 | Guard registration; enum and snapshot models; TV surfaces; shape registrations begin | 1, 8, 9 |
| 2 | Owners (25 fields → 3 records, eager), deps (incl. the `_authorization` pair), composition with its first consumer (the lifecycle); lifecycle verbatim with receivers; field-binding guard live; `setup`, `admin`, `selection` sections | 2, 3, 5 |
| 3 | `tvNav`, `save`, `grants`, `avatar`, `adminActions` sections. **Full-suite gate 1** | 3, 4, 5, 6, 7, 8 |
| 4 | `tvEditor`, `tvProfile`, `tvPanes`, `access` | 8, 9, 10 |
| 5 | `phone`, `phoneParts`; the facade keeps only lifecycle, `build` forwarder and composition | 9, 10 |
| 6 | Completion: facade registration, cap, `TEMP`, real-checker negatives, CI format/analyze paths, final evidence. **Full-suite gate 2** | All |

**Checkpoint wiring (no borrowed State members).** The order above is chosen
so that at every checkpoint a moved section calls only owners, `_deps` and
sections already moved; only the facade calls into sections (`_sections.<key>`).
Calls per step: step 2 — `setup` → `admin`; `selection` → none. Step 3 —
`tvNav` → none; `save` → `grants`, `admin`, `tvNav` (`restoreTvSaveFocus`),
own `_showRecoveryCode`; `grants` → `selection` (`defaultResourcePermissions`),
`admin`; `avatar` → none; `adminActions` → `setup` (`loadResources`),
`admin`. Step 4 — `tvEditor` → `tvNav`, `save`, `tvProfile`, `tvPanes`;
`tvProfile` → `avatar`, `selection`, `tvNav`, `tvPanes` (`tvPanel`, public rename, registered receiver); `tvPanes` → `adminActions`,
`setup`, `access`, `tvNav`, the TV surfaces; `access` → `selection`,
`adminActions`. Step 5 — `phone` → `tvEditor`, `phoneParts`, `access`,
`save`, `adminActions`, `setup`; `phoneParts` → `avatar`, `selection`. The
dependency report confirms this graph from source; if it finds a call not
listed, the member moves earlier (a plan amendment), never a borrowed State
tear-off. Each step runs a compiling + real-checker probe of its own
checkpoint before commit.

### Step 0

1. **Baselines.** `suite_evidence.py run edit_profile/base` plus whole-repo
   `flutter analyze --no-pub`, with tree and SDK provenance.
2. **Dependency report**: every leaf (fields, getters, methods, classes, enum,
   statics, comment fragments) with destination, reads/writes of each field,
   `widget`/`context`/`mounted`/`setState` sites, lexical shadowing per
   Technique 3–4, and the per-entry wiring checklist.
3. **Checker**: `dev/tool/edit_profile_manifest.tsv` (LF only),
   `edit_profile_checker_config.json`, `edit_profile_scaffolding.json`,
   `edit_profile_checker_test.py` with real-config fixtures and every negative
   in Technique 4, 5 and 7, plus: lifecycle reordered (first two and last two
   disposals swapped; `_loadSetupOptions()` moved before the seeds); an eager
   record constructed in a different order; a field's doc dropped; a
   `widget.profile` read replaced by a cached value; `_deps.policyFor`
   replaced by a local copy of the rule.
4. **Harness** `test/support/edit_profile_fixture.dart`: the existing test's
   registry/runtime setup (sqflite ffi, `AppStorage.debugOverride`,
   `ProfileRuntime`, `ProfileBootstrap.debugInstallRegistry`), helpers to
   create additional profiles, connection resources (via
   `ConnectionResourceService` with a test cipher or the registry directly, as
   existing profile tests do) and **real engine fixtures** (installed engines
   whose per-profile metadata/YAML is read back under each profile's current
   visible generation); the fixture cipher installed with the existing
   `DeviceKeyProvider.debugInstallCipher` and reset in tear-down (every real
   save reads `DeviceKeyProvider.cipher` in `_applyResourceGrants`, even with
   zero resources); a recording/holding `ProfilePinService` subclass (the
   widget takes `pins`) whose hold sits **after** the real `super` write, so
   the editor's following refresh is the boundary exercised; failure
   injection through the registry's existing `authorityWillChangeCallback`
   (fires before authority-changing writes, `profile_registry.dart:1027` and
   later sites), armed for a chosen call ordinal; a `FilePicker`
   platform fake (`FilePicker.platform = …`) returning scripted files; a
   `MainPageBridge.reloadProfilePolicy` recorder; `runAsync` pump windows as in
   the existing test. **No production seam.**
5. **Characterization through real entry points** (ORIGINAL, under
   `test/features/edit_profile/presentation/legacy_edit_profile/`; evidence
   classes R/O/S as in the catalog plan; behavioural negatives use **held**
   operations released after the triggering change):

   | Contract | Coverage |
   | --- | --- |
   | 1 Surface | Existing `policyFor` units; byte guard on lines 35–88. |
   | 2 Lifecycle | Create seeds (role member, defaults, `'person'`), edit seeds (stored policy, lock, timeout, avatar); child → `'child'`; dispose with a pending held load publishes nothing and throws nothing (R); stale authorization (the passed context invalid by the first load) surfaces the load-error tile (R, stale-rejection only). The retained lazy `late` declaration, its single first read and the exact deps getter/setter wiring are **S** evidence (checker + source guard); no R/O claim about evaluation timing or count is made. Order/structure of `initState`/`dispose` (S). |
   | 3 Ownership | **Edit another profile while admin**: every persisted change (name, role, policy, lock, timeout, grants, engines) lands on the target and nothing on the admin (O: registry re-read). Engine ownership is read from each profile's engine metadata under its current generation (target, managing admin, and any incoming profile checked). **Session change mid-save**: the PIN fake holds after its real write; the active profile switches; release → the editor's refresh throws → `'Could not save this profile'`, `_saving` cleared, grants/engines after the hold not written, writes before the hold persisted (R+O). Non-admin actor → load error / save refused (R). Policy reload called once when editing the active profile, never for another (O). Transfer: confirm → owner changed + snackbar; cancel → unchanged; session changed between confirm and write → failure snackbar, unchanged (R+O). |
   | 4 Save | Empty name no-op; loading/error snackbars; PIN validation; create (all fields, `completeStaged` visible, pop `true`); create with PIN → recovery dialog then pop; create failure (PIN fake throws) → rolled back: `getProfile(staged)` null and `listProfiles(includeStaging: true)` without it, owned avatar files cleaned, snackbar; **failure immediately before completion** (`authorityWillChangeCallback` throwing on the `completeStaged` write) → rolled back the same way, which is what kills the early-`stagedPublished` mutation; **failure after the active row is committed** (the registry's existing `authorityChangedCallback`, called by `checkpointTvOsRecovery` on every platform, armed to throw on **both** checkpoint attempts once the staged target is active — `completeStaged` retries once at `profile_creation_service.dart:162`) → two attempts recorded, no rollback, the active/setup-complete row and its avatar mutation intent retained, `'Could not save this profile'`; **single checkpoint failure** (throws once) → the retry succeeds and the save completes, pops `true`; and separately the **swallowed avatar finalization** failure after publication (both ledger temporary paths obstructed with directories so `complete()` fails) → save succeeds and pops `true`, intent slots intact; edit identity-only keeps stored policy; role change writes role defaults; TV Pages toggle writes the selection; pair-follow (downloads moved → recordings follows; unmoved → split policy preserved); Kid clamp drops `remoteTransfer`; double-tap Save saves once (O); `PopScope` blocks pop while held (R). |
   | 5 Grants | Select → grant with derived mask (use/download/writeRemote by features and role); existing grant with a stored mask unchanged on an unrelated save (O: no churn); deselect → revoke; owned row never revoked and not editable; singleton rivals deselected; All/None per group; engines All/None and own-editor read-only. |
   | 6 Avatar | Picker fake: too large (declared), too large (streamed), unreadable path, `PlatformException`, valid PNG → preview + Discard; picked during a held save is dropped; save with picked image publishes `file:`-format key (edit) and stages then commits (create); scratch copy released in every path (O: recorder on `CacheScratchCleanup` if observable, else S). |
   | 7 PIN | Admin reset success/failure snackbars and persisted state; reset visible only with a PIN or reset-required. |
   | 8 TV | Existing focus tests; failed TV save restores focus to the rail Save item (R); auto-lock dialog selection persists through save; read-only Access rows focusable. |
   | 9 Layout | Phone narrow and wide; TV compact and full-HD panes (existing). |
   | 10 Locking | While a save is held: no focus traversal, pointer absorbed, `SAVING…` label (R). |

   **Goldens** (macOS captured by the executor, strict from capture; two
   captures in reversed order must match): phone create (narrow), phone edit
   with connections and engines (wide), TV Profile pane (1280×720) and TV
   Access pane (1920×1080). Deterministic: pinned surface and DPR, fixed
   theme, `en-US`, text scale 1.0, named initial focus, no wall-clock text,
   fixed resource/engine fixtures, built-in art only.
   **Mutation proofs:** every new case first passes on (b); `original-mutations.json`
   records named mutations of ORIGINAL code, each rejected by an assertion
   (never a compile error), covering every new identity — including at least:
   target id swapped to the active profile in grants; refresh removed after a
   grant; snapshot field re-read after an await (e.g. `_selectedResources`
   instead of `snapshot.selectedResources`); `stagedPublished` set before
   `completeStaged`; rollback condition inverted; pair-follow inverted;
   `putIfAbsent` → assignment; owned-row revoke allowed; policy-reload
   condition widened; `_restoreTvSaveFocus` dropped; `_saving` not reset on
   error. Source-only expectations are classified S and listed separately.
6. **Source reader** `test/support/edit_profile_source.dart` (catalog/Debrify
   TV pattern): facade plus feature files in original manifest order with
   renames and receivers reversed, per-declaration ownership, literal-safe; a
   missing declaration fails, never skips. Switch
   `profile_source_guard_test.dart:113–151` to it, keeping **every**
   expectation string unchanged (`static const bool showFeaturePolicyControls
   = false;`, the `if (EditProfileScreen.showFeaturePolicyControls) ...[`
   count of 1, `return ProfilePolicy.defaultsFor(role);`, the `_features`
   seed expression, zero `allAllowedFor(`). Prove on (b) that positives pass
   and that a removed or duplicated hidden-controls block, a ceiling seed and
   a changed default fail through the reader.
7. **Inventory of other source-text tests** reading `lib/screens/profiles/` or
   sweeping `lib/` for profile/runtime/storage patterns (isolation suite,
   stale-runtime guard, storage checks): record which match this file and
   prove each still holds over the new locations.
8. **CI list:** add `test/profiles/edit_profile_screen_test.dart` and every
   new test (concrete paths) to `ci_behavior_tests.txt`; known failures gain
   only identities observed failing in `base`.
9. **Linux capture script** `dev/tool/capture_edit_profile_linux_goldens.sh`
   (Debrify TV script pattern, two reversed captures, checkpoint/R hash
   check, no `head`/`awk … exit` under `pipefail`).
10. **Step 0 checks:** every integrated manifest with self-tests (each with its
    own config and baseline), this one against R; architecture, sizes,
    storage, shape, theme, CI format, scoped analyzer with allowlist, staged
    diff. Commit checkpoint (b).

### Per step and gates

As in the Debrify TV plan; this feature's checks use `--baseline R` and
`--relocate lib/screens/profiles/edit_profile_screen.dart=lib/features/edit_profile/`.
Each step: wiring review before pinning; all manifests with self-tests
(isolated parser); field-binding and callback-identity checks; architecture,
sizes, storage, shape, theme, CI format, scoped analyzer with allowlist,
per-symbol strict comparison (zero additions); all focused and
characterization tests; macOS and Linux strict goldens. Gates run serially
from committed source against the latest base; gate 2 also against gate 1.
Never `--record` or `--update` to accept a regression.

## Definition of done

1. Facade ≤ its measured cap (target ≤ 200), formatted, public widget
   byte-identical, verbatim lifecycle, the lazy `_authorization`, forwarder and
   composition; callers and tests compile unchanged.
2. Guard: feature, exact bridge, bans, caps, `TEMP(edit_profile)`,
   `EDIT_PROFILE_COMPLETE = True` with every other completed flag preserved.
3. All manifests pass with self-tests; every characterization test and golden
   passes unchanged; the source guard reads the new locations with every
   expectation.
4. No new diagnostics or suppressions; any allowlisted identity traced.
5. CI lists hold the existing editor test and every new test; shape
   reconciles to the measured total.
6. Progress records commits, owners, exceptions with exits and the device
   checklist. Stop after gate 2 and report.

## Explicitly not in scope

- The three callers, `ProfileSetupFlow`, `ManageProfilesScreen`, the gate, all
  core profile services and models, `TvTextField`, `ProfileAvatarView`,
  `ProfileArtRegistry`.
- Riverpod, repositories, localization, deduplicating the TV surfaces, adding
  stale-load generations.
- Bug fixes and behaviour changes, including every Found-not-fixed item.

## End-of-series device checklist

- Android TV / tvOS: D-pad across all five rail sections and Save, the Back
  node, text-field edges, auto-lock picker, read-only Access rows, focus after
  a failed save.
- Avatar picker on Android (document providers), iOS, tvOS (unsupported path)
  and desktop; GIF and large-image rejection.
- PIN set with recovery code, admin PIN reset, create/edit with real
  connections and engines, ownership transfer, editing the signed-in profile
  (tab gating reload).

## Found, not fixed

(Step 0 completes this list; candidates noticed while planning.)
1. `_loadSetupOptions` has no request generation: a Retry while an earlier
   load is in flight lets the slower one publish last.
2. `_deselectResource` keeps the stored mask, so re-selecting restores the
   old mask rather than the current derived one (may be intended: "explicit
   grants never churn").
3. `_transferOwnership` performs its first `_validateManagingAdmin` before
   the `try`; a failure there escapes the later failure-snackbar handler.
   The step-0b stale-before-dialog case captures that escaped exception;
   the post-confirmation case demonstrates the core transfer guard masking
   omission of the second editor validation.
4. Successful admin PIN removal does not replace `widget.profile` or rebuild
   its PIN flags. The reset action can remain visible until the route reloads
   that immutable profile. Persistence and success/failure feedback are
   characterized; this refresh behavior is unchanged.
5. The original `assets/fonts/Roboto-Regular.ttf` and
   `Merriweather-Regular.ttf` contain HTML, not font data (`file` verified).
   The fixed golden theme loads the valid Inter asset; no asset was repaired.
6. After transfer of an initially unselected connection, `_loadResources`
   updates the resources without reseeding `_selectedResources`. The now-owned
   row can remain unchecked and disabled despite its owner grant. The step-0b
   ORIGINAL transfer case records that state before its later successful Save;
   no selection refresh was added.
7. The original phone connection-group header overflows by 71 pixels at
   390×844 with a real connection (`_groupHeader` Row, R line 2694).
   The 0b narrow-phone trial demonstrates it in `step0b-final-original.jsonl`;
   the passing phone write case uses 600×1000. No layout fix or exception
   suppression was introduced.

## Decisions taken before design review (Claude, 2026-10-06)

- D1 No format commit (file idempotent at R).
- D2 Records + qualified receivers + occurrence binder, not State-kept fields
  (cross-library sections cannot reach private State fields).
- D3 `_authorization` stays on the State (lazy `late` reading `widget`), behind
  a deps getter/setter pair.
- D4 Widget fields and the two statics reach sections through deps closures;
  no facade back-import and no widget view object.
- D5 Private classes keep runtime types via typedefs (enum, snapshot, TV
  surfaces); no renames of runtime types.
- D6 Goldens are included (renderer moves across five TV panes and the phone
  form); Linux originals by Claude in Docker before step 2.
- D7 No size exception is authorized; `_save` is 270 lines and its file is
  estimated at 355.

## Round 1 review resolution

1. P1 binder: Technique 4 now requires config-scoped `state_classes` and
   registered occurrence substitutions (widget fields, statics, the retained
   `_authorization` pair, nested chains), proved through checker and reader at
   step 0 and by the 0b compiling probe.
2. P1 ordering: Contracts 3–4 restate the exact original sequences (actor read
   after the avatar prepare; create PIN → update → refresh; live
   `_policyTouched`/`widget.profile` reads after awaits); nothing hoisted,
   added or normalised.
3. P1 early publication: failure injection before `completeStaged` via
   `authorityWillChangeCallback`, rollback asserted with `getProfile` and
   `listProfiles(includeStaging: true)` plus file cleanup; a separate
   post-completion failure case.
4. P2 intermediate wiring: steps reordered (`tvNav` at 3, `access` at 4) with
   an explicit per-step call graph; no borrowed State tear-offs; per-step
   compiling probe.
5. P2 harness: `DeviceKeyProvider.debugInstallCipher`, real engine fixtures
   read per profile generation, post-write PIN hold.
6. P2 hazards: `_loadResources`, `_validateManagingAdmin(context)`, and the
   `build`/`_buildTvEditor` `context` parameters added.
7. P2 laziness: reclassified as S evidence; stale-authorization stays as R.

## Round 2 review resolution

No P1s. P2: post-commit failure recipe made explicit (`authorityChangedCallback`
throwing on both checkpoint attempts; single-failure recovery and swallowed
avatar finalization as distinct cases). P2: `tvProfile → tvPanes` edge
(`tvPanel`) added. P3: step 6 row moved into the table.

## Progress

### Step 0 — ORIGINAL characterization, 2026-10-06

- **Execution base R:** `f9ffe16d5e7ee9a94402950d7debdb359d1fc8f8` on
  `refactor/edit-profile`. Flutter **3.44.8**, Dart **3.12.2**;
  `flutter pub get` left the lockfile unchanged. No format commit: the
  original editor is formatter-idempotent. Checkpoint (b) preserves R's
  `lib/`, `pubspec.yaml` and `pubspec.lock` objects. No production seam or
  profile-service edit. The sole detached ORIGINAL copy is inside this
  worktree at `.dart_tool/edit_profile_original/`.
- **Evidence root E:** `<git-common-dir>/refactor-evidence/edit_profile/`
  (`/Users/varunbsalian/Documents/Projects/debrify/.git/refactor-evidence/edit_profile/`).
  Evidence names below are relative to E. Inputs/commands, SDK and tree
  provenance accompany the logs; no evidence is committed into application
  paths.
- **Baseline:** `python3 dev/tool/suite_evidence.py run edit_profile/base
  --no-pub --concurrency=2`, serial under concurrent sibling load, Flutter exit 1:
  `{'success': 11654, 'failure': 13, 'error': 28, 'skipped': 20}`.
  `base.env.json` records an unchanged tested tree; `base.jsonl`,
  `base.stderr`, and `step0-test-identities.json` preserve observed identities.
  The WebDAV appearance failure repeats in isolation with the same assertion
  (`webdav-hot-merge-isolation.jsonl`, `load-sensitive-note.txt`); no PIN-settle
  failure or allowlist/failure-list update. `flutter analyze --no-pub` found 1,689
  diagnostics (`base-analyze.txt`); final analysis has the same identities,
  zero additions/removals (`step0-analyze-final.txt`,
  `analyzer-comparison.json`).
- **Inventory and checker:** 2,764 lines, **28 import declarations**, nine
  classes plus the enum, **90 manifest leaves**, 81 State members and 26
  State fields. Twenty-five fields are assigned to the three frozen owners;
  the lazy `_authorization` stays on State. The dependency report records
  each destination, occurrence binding/read/write, live dependency site,
  lexical hazard, comments and wiring checklist. Facts were remeasured,
  not copied from the scratch inventory (`facts-verification.json`,
  `original-ast.json`, `dependency-call-graph.json`).
- **Strict probes (Technique 2):** ORIGINAL imports: three infos;
  partial compiling same-State owner/live-dependency receiver probe: six
  infos; whole-leaf cross-library typedef/constructor-forwarder probe:
  five enum-field warnings and eight infos, no errors. The per-identity
  maximum inventory has 16 diagnostic occurrences
  (`dev/tool/edit_profile_analyzer_inventory.json`,
  `strict-*-probe-provenance.json`). Three exact constructor forwarders
  remove the six optional-parameter warnings without modifying original
  constructors/defaults/keys. Their syntax is frozen in the sidecar; no
  current analyzer allowlist addition. Full compiling section composition
  remains **0b**, unstarted.
- **Harness and cases:** real registry/runtime/SQLite, installed engine
  metadata and YAML under each profile's visible generation, test cipher,
  PIN hold after `super` write, registry authority callbacks, scripted
  picker and policy-reload recorder. Added **50 behavioral cases + four
  goldens = 54 identities** across four concrete test files, all passing on
  ORIGINAL (`original-final-all2.jsonl`, final strengthened preview replay
  `original-preview-final.jsonl`). Every identity is covered by a named
  original-code assertion failure: **54/54 behavioral mutants proved**,
  plus **8/8 separately classified S mutants** through checker, reader and
  the retained source-guard test (`original-mutations.json`,
  `step0-case-coverage.json`, `mutations/`). Reproduce with
  `python3 dev/tool/edit_profile_original_mutations.py --original-root
  .dart_tool/edit_profile_original --parser-package
  .dart_tool/edit_profile_parser/inventory/.dart_tool/package_config.json`
  and the equivalent `edit_profile_source_proofs.py` command. Initial
  survivors/rejected proof attempts are retained in `audit_attempts`;
  registry-decoded clamp omission and core-protected active rollback are
  **S only**, not behavioral kills. The direct disposed-load mutant fails
  Flutter's explicit State lifecycle assertion, with its editor stack frame
  recorded; it is separate from the loader-invocation proof. No compile/setup
  failure is accepted.
- **Source reader / sweeps / CI:** the original source-guard expectation
  strings and comments are unchanged; only the reader/import changed.
  Removed/duplicated hidden controls, ceiling seed and changed default fail
  through the reader on ORIGINAL. Global storage/profile/cache/player
  forbidden-pattern counts are zero across the actual syntax destinations
  (`source-text-and-surface-inventory.json`, `final-evidence-audit.txt`).
  Shape regex: **13**, broader circular search: **14** (one conditional
  radius); editor outside shape/theme manifests and PRIMARY light-ink set.
  Existing editor test plus all four new files appended to CI; both support
  files appended to its format command. Focused existing editor, profile,
  isolation, shape and theme checks: **72 visible passes / one failure**
  (82 success events including loading, one failure), the same baseline
  raw-preferences guard violation; existing editor's 22 cases pass
  (`step0-focused.jsonl`).
- **macOS goldens:** four readable Inter scenes captured on R twice in
  separate processes, first PNGs removed before reverse-order capture;
  hashes identical, then all four strict replays pass. Phone 390×844 create,
  phone 1100×1600 edit with real connections/engines, TV Profile 1280×720,
  TV Access 1920×1080; all four visually inspected. Commands/hashes in
  `macos-original-provenance.json`, logs `macos-original-{first,reverse,strict}.jsonl`.
  Linux script prepared and `bash -n` passes; **L unstarted** as requested.
- **Step 0 checks:** edit-profile's real-config ORIGINAL and syntax-move
  positives plus reader pass; **169 negative proofs**, including **17**
  independent same-class callback identity checks. All manifest runs use
  their own config/baseline and isolated `--parser-package` below
  `.dart_tool/edit_profile_parser/`, deleting copied `*.dill`.
  Shared edits are opt-in/config scoped. **All 17 manifests pass with
  self-tests: 16 existing (Debrify TV included) plus edit-profile**, each
  against its own baseline (`all-checkers.json`, `checker-*.txt`).
  Architecture, size, storage map/bodies/keys/references
  (with available self-tests), Linux script syntax and actual CI formatting
  pass (`static-checks.json`). Scoped CI analyzer: 323 diagnostics;
  allowlist check: 25 existing warnings, nothing new
  (`step0-scoped-analyze.txt`, `step0-analyzer-allowlist.txt`).
- **Checkpoint (b):** `test(edit-profile): step 0 original-code characterization checkpoint`.
  The 31-path staged diff was reviewed; LF, document links, public-widget
  bytes, unchanged original source assertions/comments, and golden hashes
  pass (`staged-review.json`, `step0-staged-diff.txt`). Commit SHA and R/b
  application-object equality are recorded in `checkpoint-provenance.json`.
- **Found-not-fixed additions:** initial transfer validation outside its
  feedback handler, unchanged PIN flags after reset, invalid original font
  assets (items 3–5 above). No bug fix, device/emulator run, Linux capture,
  independent 0b review, base2, or extraction has been performed.


### Step 0b — independent review closure, 2026-10-06

- **Scope / R:** closes G1–G8 from checkpoint `36b6288d`; R remains
  `f9ffe16d5e7ee9a94402950d7debdb359d1fc8f8`. No application move, production
  seam or core-service edit. `lib/`, pubspec and lock objects remain R.
  All evidence below is under `<git-common-dir>/refactor-evidence/edit_profile/`.
- **ORIGINAL cases:** 23 new cases in `edit_profile_review_closure_test.dart`,
  appended to CI. `flutter test --no-pub --concurrency=1 --reporter=json`
  against the owned ORIGINAL copy passes the 109 visible editor cases
  (50 prior + four strict macOS goldens + 23 closure + 32 existing).
  The final 23-case replay includes direct creation/transfer core rejection
  stacks (`step0b-final-original2.jsonl`, `step0b-final-original4.jsonl`).
  **No new goldens**; the four originals are unchanged.
- **Mutation closure:** `edit_profile_original_mutations.py --only 0b-…`
  and `edit_profile_review_mutations.py`, with `--original-root` and the
  isolated inventory `--parser-package`, prove **27 assertion-failing
  mutations + two S demonstrations**. All 23 identities are covered:
  20 behaviorally killed, three core-masked contexts; 28 unique mutant
  sources. `original-mutations.json` retains every prior proof (54 B / 8 S),
  giving **81 B / 10 S** total; commands, assertions, source/test hashes and
  initial rejected attempts remain recorded (`step0b-final-mutation-audit.json`,
  `step0b-gap-closure.json`, `step0b-final-{behavior,source}-mutations.txt`).
  Create's omitted start guard is masked by `createStaged`'s first
  `actor.validate`; both stale/demoted contexts still refuse staging.
  Transfer's omitted prewrite guard is masked by `transferOwnership`'s first
  `actor.validate`. Both mutants actually run, core stacks are asserted,
  and checker, reader and existing source-guard assertions reject them.
- **Compiling composition:** `python3 dev/tool/edit_profile_composition_probe.py
  --parser-package .dart_tool/edit_profile_parser/composition/.dart_tool/package_config.json`
  applies all 90 manifest leaves (86 destination leaves) in owned scratch.
  Real checker/reader pass occurrence bindings/substitutions, callback
  identity, public bytes, lifecycle and 100 exact new scaffold leaves.
  Facade **150 lines**: public widget 54, composition 20, authorization 1,
  lifecycle 45, build 2, imports/header/blanks 28. Per-span breakdown and all
  file sizes are in `step0b-composition-probe.json`; every probe file <500.
  Strict analyzer: **0 errors / 5 known enum warnings / 5 infos**, by original
  identity. Two infos arise from wrapped receiver qualifications in frozen
  original control statements; no suppression or allowlist change
  (`step0b-composition-analyzer-identities.json`, analyzer inventory).
- **Checks:** all **17 manifests** pass their live configs and self-tests,
  Debrify TV included; edit-profile proves **169 negatives**, including
  **17 same-class callback identities** (`step0b-all-checkers.json`). Every
  parser is isolated below `.dart_tool/edit_profile_parser/`; copied kernels
  are deleted. Shared checker sources remain byte-identical; config adds
  only edit-profile callback aliases, CI only appends the new test path.
  Whole `flutter analyze --no-pub`: **1689 diagnostics, no added identities**;
  actual CI formatting, architecture, size, storage map/bodies/keys/references
  and script syntax pass (`step0b-analyze-comparison.txt`, `step0b-static-checks.json`).
- **Checkpoint / base2:** subject
  `test(edit-profile): step 0b independent review closure`.
  The full suite runs serially at this committed checkpoint with
  `python3 dev/tool/suite_evidence.py run edit_profile/base2 --no-pub --concurrency=2`;
  its exact result line and identity verdict against `base` are retained in
  `base2-summary.txt`, `base2-comparison.txt` and `base2-comparison.json`.
  `base2.env.json` records the checkpoint, SDK and unchanged execution tree;
  `step0b-checkpoint-provenance.json` ties the final audit to that revision.
- **Found-not-fixed:** item 3's pre-dialog exception is exercised; additions
  6–7 record the stale unchecked owner row after transfer and ORIGINAL's
  390-pixel phone connection-header overflow. Passing phone persistence uses
  600×1000, with real phone role/art/checkbox actions and no preseeded grant.
  No regression acceptance, device/emulator run, push or merge. **L and
  step 1 remain unstarted.**

### Step L — strict Linux originals, 2026-10-06

Claude committed `791aa4e87`: four ORIGINAL Linux PNGs captured from
`36b6288d` in `debrify-flutter:3.44.8` linux/amd64. First/reversed captures
are byte-identical; strict replay passed at the capture checkpoint and at
`791aa4e8`. Local SHA-256 verification matches all four entries in
`refactor-evidence/edit_profile/linux-original-verification.json`; the
pending-capture skip is removed. Claude owns Linux replays at gates 1 and 2.

### Step 1 — extract models and TV surfaces, 2026-10-06

- **Commit:** `refactor(edit-profile): step 1 extract models and TV surfaces`. Previous checkpoint
  `791aa4e87`; R remains `f9ffe16d5e7ee9a94402950d7debdb359d1fc8f8`.
- **Files (formatted physical lines):** facade **2489**; edit_profile_snapshot.dart 41; edit_profile_tv_section.dart 3; edit_profile_tv_surfaces.dart 269.
- **Verification:** wiring reviewed before pinning; compiling checkpoint,
  real 90-leaf checker/reader, occurrence bindings/substitutions and callback
  identities pass. All **17** manifests/self-tests pass with isolated parsers
  (Debrify TV: 265 leaves / 236 callback negatives). Architecture, sizes,
  storage, shape (**13**, global floor unchanged), theme exclusion, CI format
  and scoped analyzer/allowlist pass. Strict comparison: **6** diagnostics,
  **zero additions**. Focused/characterization identities match base2:
  **177 success / 1 unchanged known source-guard failure**, zero missing or
  newly skipped; all **4 macOS** originals pass strictly. All **103** original
  comments, core services and dependency files stay byte-identical.
- **Evidence:** `step1-*` under `refactor-evidence/edit_profile/`; commands,
  wiring/scaffold review, per-symbol diagnostics, source hashes/counts and
  comparisons included. No behavior fix, seam, borrowed State action or
  size exception; Found-not-fixed items remain.
- Five enum `unused_field` warnings are recorded at the new model path with
  a dated R comment. Unfinished fixtures were rerun using the existing exact
  syntax-unit cache (batch/per-unit equality in both modes, defensive copies);
  all assertions run and the production CLI comparison stays uncached.
