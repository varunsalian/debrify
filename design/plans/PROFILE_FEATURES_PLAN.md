# Profile Features Questionnaire & Sources Editor — build plan

2026-08-16. Spec: `design/mockups/profile_features_mockup/` (mock v6 +
audit + owner dispositions). Companion decisions: the six-permission grant
UI is retired; features are profile-level; sources are admin-curated
grants; catalog search is never a permission.

## The discovery that shapes this plan

The enforcement substrate ALREADY EXISTS. This is UI + alignment work, not
architecture:

| Mock concept            | Existing code                                        |
|-------------------------|------------------------------------------------------|
| Keyword search          | `ProfileFeature.torrentSearch`                       |
| Manage own sources      | `ProfileFeature.addonsAndEngines`                    |
| Debrify TV / Stremio TV | `ProfileFeature.debrifyTv` / `.stremioTv`            |
| Live TV / YouTube       | `ProfileFeature.iptv` / `.youtube`                   |
| Downloads & recording   | `ProfileFeature.downloads` + `.recordings`           |
| Remote                  | `ProfileFeature.remoteControl` + `.remoteTransfer`   |
| Cloud files             | `ProfileFeature.cloud`                               |
| NSFW rail               | `ProfileFeature.allowAdultContent` + `NsfwFilter` + the **role ceiling** (`_roleCeilingAllows`) |
| Role presets            | `ProfilePolicy.defaultsFor(role)`                    |
| Boundary enforcement    | services check features at operations; remote lease copies `policy.enabled`; comprehensive export admin-gated |
| Sources grants          | `ConnectionResource` + registry grants; engines via `ProfileEngineAssignment`; addon seeding exists |
| Raw switch UI           | `EditProfileScreen` already renders feature checkboxes + the six-permission matrix (this is what the questionnaire replaces) |

What does NOT exist: UI reach-sweep hiding (features are enforced but
surfaces still render), the questionnaire, the sources editor, default-on
grant semantics, and the preset deltas the mock specifies.

## Rules carried from the spec (non-negotiable)

- Secrets owner-only; connection manage/delete owner-only; share-onward
  concept deleted (Phase 6).
- NSFW: viewer-scoped, role-locked — evaluated against the ACTIVE profile
  at browse/play; forced for `role == child` via the ceiling, regardless of
  who authored a channel. No toggle exists in a child session.
- Sources default ON for every profile — EXCEPT tracker connections
  (personal history). New resources inherit the default; trims are
  per-resource, not a mode.
- Reach sweep covers: nav tabs, Home rows, settings pages, settings-search
  entries, startup conveniences, remote commands (lease already does).
  Deep links accepted as-is per disposition. Hiding is courtesy; the
  boundary stays the guarantee.
- Copy: profile pronouns = name or they/them. `ConnectionResourceType.reddit`
  is a vestige — the editor must NOT grow a section for it.

## Phase 1 — Policy alignment (model only, no UI)

1. `defaultsFor` deltas: Member loses `cloud` (mock matrix); Child
   additionally loses `torrentSearch`, `addonsAndEngines`, `stremioTv`,
   `iptv`, `youtube`, `cloud`, `remoteControl` (keeps `debrifyTv`,
   catalog browsing, `externalPlayers`, `incomingLinks` per dispositions).
2. Ceiling: add `allowAdultContent` to the child ceiling so it is
   non-grantable, not merely default-off. Audit whether `cloud` for
   member should be ceiling or default — DEFAULT (a member can be granted
   cloud deliberately).
3. Migration: existing profiles predate any feature UI, so their policies
   are untouched `defaultsFor` snapshots — re-derive on a policy version
   bump. Rule: if `policy == old defaultsFor(role)`, replace with new
   defaults; custom policies (none can exist yet) untouched.
4. Tests: extend `profile_policy_test` with the full mock matrix +
   ceiling assertions; isolation suite must stay green.

## Phase 2 — Reach sweep (UI gating)

Surface inventory per feature (each row = "off ⇒ invisible"):

- **Nav**: phone bottom nav + More sheet; TV sidebar + command grid.
  ⚠ THE HAZARD: `MainPageBridge.switchTab(int)` + hardcoded indices
  project-wide (nav-index audit memory). Mitigation is a prerequisite
  step: introduce a `TabId` enum + resolver (`indexOf(TabId)` against the
  profile-filtered tab list), convert every `switchTab(N)` call site, THEN
  filter tabs per profile. Tabs rebuild on profile switch (sessionEpoch
  rekey already exists in ProfileGate).
- **Home**: IPTV rows/custom-list rows (`iptv`), Debrify TV shelves
  (`debrifyTv`), YouTube-derived rows if any (`youtube`).
- **Search screen**: keyword segment/results (`torrentSearch`) — catalog
  title-search remains for everyone.
- **Settings**: pages + settings-search entries of gated features
  (IPTV settings, Debrify TV settings, download settings, Remote,
  Cloud accounts pages…). The Profiles card itself stays.
- **Startup**: IPTV boot-to-channel honors `iptv` (wall already clears
  session conveniences; add the feature check where the convenience fires).
- **Actions**: download/record buttons (`downloads`/`recordings`),
  Remote FAB/rows (`remoteControl`).
- Pattern: one helper (`ProfileRuntime.currentAllows(feature)` reading the
  active profile snapshot, listenable across profile switch) so gates are
  one-liners; every gate device-agnostic (phone AND TV hide equally).
- Tests: per-surface widget tests (feature off ⇒ finds nothing); a sweep
  test iterating features against the settings-search index.

## Phase 3 — NSFW rail (viewer-scoped)

1. Route every `NsfwFilter` consultation through the active profile:
   `storage_service` already exposes the check — sweep Debrify TV
   (channel create/edit/browse/play), keyword results, and any
   "allow adult" toggles to consult it.
2. Child sessions: toggle UIs hidden (ceiling makes the value
   unreachable anyway).
3. Tests: viewer-scoped assertions — admin-authored NSFW-allowed channel
   filters for a child viewer.

## Phase 4 — The questionnaire (mock v6)

Build ON the onboarding kit — it already solved responsive + DPAD + TV
text entry:

- `OnboardingTheme.scope` for the fixed Spotlight look (gates and
  onboarding are para-profile surfaces; same rationale as the wall).
- `resolveOnboardLayout` → phone (<600, stacked single-column), tablet
  (2-col cards), stage/TV (onboarding stage grammar: identity block left,
  cards right; ONE question per screen on every tier — remote-friendly by
  construction).
- `OnboardFocusController` + `OnboardFocusable` for the DPAD grid
  (cells as (row,col); back-parking; the sources-pages multiselect is a
  2×2 grid of cells). Landing focus TV-only (already gated).
- `TvKeyboardSlot` for the name field on TV.
- Identity step reuses EditProfileScreen's avatar picker components + PIN
  flow; role step = preset application (prefill, never lock).
- Review: Can/Can't chips + "Sources" summary + Fine-tune expander that
  EMBEDS the existing EditProfileScreen feature list (collapsed) — the six
  -permission matrix does NOT appear (Phase 6 deletes it).
- Entry points: Profiles settings card (Add/Edit rows), hub create, wall
  Manage→create. Editing later lands on Review; "Re-run questions"
  re-enters at role. RULE: when editing, the questionnaire reflects
  CURRENT values — presets only seed CREATE.
- Tests: per-step widget tests at all three layouts; DPAD traversal tests
  (the onboarding focus test idioms); preset-prefill and divergence tests.

## Phase 5 — Sources editor + default-on semantics

1. Semantics first (registry): on resource creation → auto-grant every
   profile (skip tracker types); on profile creation → auto-grant all
   existing non-tracker resources; trim = revoke grant; one-time backfill
   migration for existing resources. Tracker exception is type-based.
2. Editor UI: one section per `ConnectionResourceType` KIND (addons,
   debrid & cloud, trackers, live TV, indexers — reddit skipped) + an
   Engines section backed by `ProfileEngineAssignment`. Rows = tick per
   profile-being-edited. Admin-only (`manageProfiles`).
3. Reached from Review + Edit Profile. DPAD: rows are a single focus
   column; section headers not focusable.
4. Tests: default matrix (new profile/new resource/tracker exception),
   trim persistence across restarts and profile switches, editor widget
   tests, engines-assignment integration.

## Phase 6 — Grant collapse (cleanup, LAST)

1. Sharing becomes binary; `ResourcePermission` bits become DERIVED at
   authorize-time: `use`+`download` from the grant, `writeRemote` from
   grant + profile `remoteTransfer`, `manage`/`revealSecret` owner-only,
   `share` removed. No storage migration if derivation happens in
   `authorize()`.
2. Delete the six-checkbox matrix from EditProfileScreen; adapt
   restore-coordinator expectations (it currently checks writeRemote+share).
3. Tests: derivation table; the credential/collection facade suites and
   restore coordinator suite must stay green unchanged where behavior is
   equivalent.

## Verification matrix (every phase that touches UI)

- Phone (OnePlus, portrait + landscape), tablet width (resize/desktop
  window), desktop wide, Android TV DPAD (Mi Box), tvOS. Text scale 1.3
  pass on the questionnaire (onboarding bands test idiom).
- DPAD walkthrough script: wall → create → all steps → review → sources
  editor → back-chain to wall, LEFT-parking on Back at every step.
- Profiles isolation suite + settings suites green after every phase.

## Sequencing, size, risk

P1 (S) → P2 (L — the TabId refactor is the bulk and pays the nav-audit
debt) → P3 (S) → P4 (L) → P5 (M) → P6 (M). P1–P3 ship value with zero new
UI (safety + hiding); P4/P5 are the visible feature; P6 is debt removal.
Everything rides the existing profiles flag set (still off), bisectable
per phase. Risks: nav-index conversion (mitigated by resolver + tests);
grant backfill on large installs (idempotent migration, measured);
questionnaire-vs-EditProfileScreen duplication during transition
(Fine-tune embeds rather than forks).

## Open questions (decide at build time, none blocking)

1. Does Fine-tune expose `externalPlayers`/`incomingLinks`/`appUpdates`
   too (full enum) or only the questionnaire ten? Lean: full enum —
   Fine-tune is the escape hatch.
2. Member self-editing identity (name/avatar) without `manageProfiles` —
   currently admin-only; questionnaire keeps admin-only, revisit later.
3. Trakt/Simkl FEATURE (`trackersAndDiscovery`) stays ON for Kid while
   tracker CONNECTIONS default off — confirm the tracker-less experience
   degrades gracefully (local CW only).

## Review corrections (2026-08-16, pre-build adversarial pass)

Verified against boundary consumers; three findings amend the phases:

1. **`cloud` gates provider CREDENTIAL READS** (`profile_credential_facade.dart:41-62`
   maps provider slots → `ProfileFeature.cloud`), not just pages. Member-minus-cloud
   would break debrid playback. → P1 adds a distinct `ProfileFeature.cloudFiles`
   (page visibility, the mock's toggle); `cloud` stays ON for Member. The
   questionnaire's "Cloud files" maps to `cloudFiles`.
2. **`torrentSearch` gates ENGINE EXECUTION** (`dynamic_engine.dart:443`).
   Kid-minus-torrentSearch would break engine-backed title→stream resolution,
   contradicting the engines-for-kids decision. → P1 scopes the feature to the
   keyword-search SURFACE; engine execution defers to engine grants
   (ProfileEngineAssignment). Audit every `torrentSearch` consumer
   (indexer_manager_service, settings guards, main.dart) and classify
   surface-vs-operation before flipping the Kid default.
3. **Reach sweep is PARTIALLY BUILT**: `main.dart:1478-1495` filters tabs by a
   hardcoded index→feature switch (2,3,4..16,18,19 → features), and settings
   has `_ensureProfileFeature` guards. → P2 re-scoped: the TabId refactor's
   first target IS that switch (nine magic numbers bound to features); the
   genuinely missing surfaces are Home rows, the search keyword segment,
   download/record buttons, and the IPTV startup convenience. Size drops L→M.
4. **Policy migration must bump `authorizationRevision`** per rewritten
   profile — remote leases and captured async authorizations key on it; a
   silent policy rewrite would leave stale feature sets live until relock.
5. Minor: questionnaire route uses the InitialSetupFlow.show pattern
   (rootNavigator push wrapped in OnboardingTheme.scope); Fine-tune embeds an
   EXTRACTED feature-checklist widget from EditProfileScreen (no fork).

## Implementation outcomes (2026-08-16, P5/P6 as built)

- **P5.1 semantics** built at the REGISTRY layer (`profile_registry.dart`):
  `_seedDefaultGrantsForProfile` / `_seedDefaultGrantsForResource`, hooked into
  `createProfile` + `insertResource` transactions. Seeds `use|download`,
  `ConflictAlgorithm.ignore` (never downgrades explicit grants), skips
  `personalResourceTypes` (trakt/simkl/mdblist/reddit). No backfill migration:
  profiles are unshipped, so no multi-profile installs with resources exist.
  Known follow-up: seeds do not auto-BIND singleton credential slots; the
  first explicit grant or editor save does (service.grant passes bindingSlot).
- **P5.2 editor**: NOT a new screen. EditProfileScreen's Access section
  already renders per-kind groups + engine assignment + per-profile ticks —
  it IS the sources editor. Amendments: reddit excluded (vestige), and the
  flow's Review "Full editor" row now names sources & engines. Trackers show
  unticked by default purely because no grant was seeded.
- **P6 split**: the six-permission FilterChip matrix is DELETED (sharing is
  binary in UI). Masks for newly ticked resources derive from the feature
  policy via `_defaultResourcePermissions` (use always; download from
  downloads/recordings; writeRemote from remoteTransfer, non-child) — i.e.
  derivation happens at GRANT-WRITE time. Authorize-time derivation (P6.1)
  is DEFERRED deliberately: it would touch every facade + restore
  coordinator for zero user-visible change, and stored masks remain a
  correct superset semantics under the existing authorize().

## Review round (2026-08-16, two agents over the full uncommitted diff)

Confirmed clean: MainTab↔_pages order, policy v2 presets + v1 upgrade,
keyword-gate entry points, legacy-mode fail-open, policyFor split.
Findings, all fixed same day:

- **P0** Debrify TV QUICK-PLAY missed the NSFW force-lock (channel flows had
  it): five `_quickAvoidNsfw` filter sites now OR `_viewerForcesNsfw`, and
  the quick-scope options SwitchRow is role-locked like the other dialogs.
- **P0** Questionnaire DPAD: footer sat on row 90 but the focus grid has no
  gap-bridging — unreachable from every step. Footer row is now contiguous
  per step, review actions renumbered 0/1, and the name field registers its
  focus node at row 0 (key_step idiom) with TV-only autofocus.
- **P1** Untouched edit-save re-authored unasked features from role
  defaults. `_buildPolicy` now bases on the STORED policy when the role is
  unchanged; a role change is a re-preset (Review says so). The coupled
  pairs (downloads/recordings, remote/remoteTransfer) only follow their
  toggle when the answer actually moved.
- **P1** EditProfileScreen `_features` seeded from `allAllowedFor(role)`,
  handing writeRemote to every newly ticked resource — now seeds from the
  stored policy (create: role defaults), matching what policyFor writes.
- **P2** Active-profile self-edit left MainPage/_policyGuard mirrors stale:
  new `MainPageBridge.reloadProfilePolicy` hook, called from both editors
  when the saved profile is the signed-in one.
- **P2** Seeder now skips resources inserted disabled (mirrors the
  profile-side filter); re-enable stays an accepted, documented gap.
- **P2** Last literal tab indices: main_page_bridge's own `15`s and the
  calendar's `'originTab': 19` → MainTab constants.
- Flow save error now names the admin-invariant failure instead of the
  generic retry line; BACK from Review reports full-editor changes via the
  show() contract; edit test fixture diverged so the round-trip is pinned.

## On-device findings (2026-08-16, first real kid profile)

1. **addonUse split (4f093160)**: getAddons demanded addonsAndEngines →
   Kid Home threw "Profile authorization does not allow this feature".
   Policy v3 `addonUse` = addon-READ operation, all roles, never asked;
   management keeps addonsAndEngines. Decode upgrade heals stored policies.
2. **Engine seeding (5c6dba6f)**: engines are per-profile FILE COPIES, not
   connection resources — grant seeding can't cover them. The questionnaire
   create now assigns every manager engine (the full editor's old default).
   Profiles created before this fix have zero engines: repair via Full
   editor → Access (or recreate the profile).

Lesson pinned in memory: every feature a preset turns OFF must be audited
for OPERATION consumers, and every per-profile store (grants, engines,
prefs) needs its own seeding story — one mechanism never covers both.
