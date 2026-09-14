# Debrify Cross-Device Sync over WebDAV — Implementation Plan

Addenda status (2026-09-03): §13 (scalar provenance repair), §12
(near-real-time propagation), and §11 (silent per-record sync for
connections, addons, and profiles) are all IMPLEMENTED on `webdav-sync`,
in that order. The graph tier is now bootstrap-only. §11 shipped with the
design-round corrections recorded in the git history (registry v7 shape,
(profile, slot) binding keys, applySyncedRegistryDelta, nullable stamped
leaves as tombstones, owner-scoped secrets under the full existing reveal
authorization); where §11's original text conflicts, the shipped code is
authoritative. Remaining manual gates: the physical Koofr cross-device
re-test and the deferred provider-compat checks from the v1 status below.
Sections 1–10 describe v1 as implemented, except where §13 explicitly
supersedes the original whole-scalar conflict rule.

Status: M1–M6 IMPLEMENTED on `webdav-sync` (2026-09-02); automated acceptance
gates, the simulated phone/Mi Box/tvOS/desktop convergence matrix, and a
real-provider Koofr M1/M2 smoke test pass. M3/M4 remained dark until M5
completed activation, adoption, and the graph tier; the rollout now defaults
on with an emergency dart-define override. The version-pinned Nextcloud 34.0.3,
physical-tvOS, and physical cross-device soak checks remain explicitly deferred
manual compatibility gates; none is claimed as tested. The twelve reviewed
architecture rounds remain the
safety baseline, with the login-first product-flow amendment in §15:
sync uses a dedicated in-memory WebDAV login and the fixed `Debrify` folder;
the app automatically initializes or connects to the sync data found there.
“Circle”, “seed”,
“join”, and “enrollment” are internal protocol terms, never user-facing
concepts. Every later invariant below is encoded as a test in its owning
milestone before it is trusted.

**Known correctness blocker (physical Koofr Mac ↔ Android, 2026-09-02):**
ordinary scalar preferences currently share one provenance stamp. Android
therefore republished a stale `default_torrent_provider_v1 = none` 15 seconds
after macOS published `torbox`, and the newer whole-section stamp made the
stale value win permanently. This was verified from the authenticated remote
hot documents, not inferred from UI state. §13 replaces whole-scalar
arbitration with per-setting provenance before this work is considered ready
to ship.

Goal: everything the app considers "the user's state" — profiles, connections,
addons, playlists, favorites, settings, watch progress, source bindings —
follows the user across devices, via a user-supplied WebDAV server, encrypted
client-side, with no Debrify-run infrastructure. **Database carve-out
(2026-09-02, superseded by §14 on 2026-09-03):** each device still rebuilds
its IPTV channel catalogue and EPG cache locally. Everything personal now
syncs continuously: IPTV source credentials, favorites, watch history,
resume, hidden categories and arrangements, plus Debrify TV channels and
their hash pools travel as live per-record library state (§14). Playlists and playlist favorites are prefs
(`user_playlist_v1`, `playlist_favorites_v1`) and DO hot-sync.

Design priorities, in order: **low bug surface → durability → few days**.
Almost every hard problem is solved by machinery that already shipped and
survived review. New code is thin glue, one merge module of pure functions,
one adoption flow, and UI.

---

## 1. The three decisions that make this small

### D1 — The sync payload IS the existing `deviceGraph` package (+ a small hot document)
`ProfilePackageService.exportAllProfiles` (`lib/services/profiles/profile_package_service.dart:181`)
already produces the complete, fought-over definition of "everything":
all profiles + PIN hashes + avatars + policies, all connection resources with
sealed secrets, per-profile portable preferences, DB snapshots, portable
files. Its omissions list is the right sync exclusion list (device keys,
pairings, OS grants, local paths, caches, download binaries). Rules:

- Full database snapshots are preferred. If their raw total exceeds the
  portable-package budget, the existing bounded fallback removes only IPTV
  catalogue/EPG cache tables and Debrify TV channels/hash pools from scratch
  snapshots. IPTV credentials travel as encrypted connection resources and
  durable IPTV tables remain in the compact snapshot.
- Only the validated `rebuildableDatabaseCachesOmitted` and
  `debrifyTvChannelsOmitted` records are accepted. Any unknown/malformed
  omission or a package still oversized after compaction **refuses** the push
  and keeps the prior graph section.

`ProfilePreferencePortability` already classifies every pref: credentials
blocked (travel as sealed resources instead), device-local blocked,
`playback_state_v1` stripped of URLs/paths but **kept**, `series_source_*`
stripped of local pins but **kept**. We invent no new taxonomy. Ever.

### D2 — Adoption, not merge, for the graph
Cross-device profile identity is the only genuinely hard problem, so we
delete it: internally, **a sync folder has one seed graph**. The first device
uploads its graph; later devices adopt it when needed. We never merge two
pre-existing profile registries.

**Product model (amended by §15): the dedicated WebDAV account plus its fixed
`Debrify` folder is the sync identity.** The user never chooses “start” versus
“join”, browses folders, names a circle, enters a passphrase, or handles an
enrollment code. After login the app probes the hidden
`Debrify/debrify-sync/circle.authority`:

- **unbound device + authority absent** → probe legacy names; if those are
  absent, generate a machine secret and stage a new encrypted sync set locally;
- **unbound device + valid authority present** → extract its secret,
  authenticate its embedded marker, require at least one authentic complete
  bootstrap-bearing manifest, and connect automatically;
- **malformed authority present** → fail closed without probing or overwriting
  legacy names;
- **unbound device + marker present + keyfile absent** → fail with the
  legacy-root recovery instruction; never ask for or guess a passphrase;
- **repair/reconnect of a pinned legacy binding + marker present + keyfile
  absent** → authenticate the pinned marker with the locally sealed secret,
  then provision and read back one merged authority object;
- **already-bound device + matching pinned authority bytes** → continue
  normally;
- **already-bound device + 404 or different authority bytes** → hard
  `RootChanged`; never recreate or reinterpret the folder as new. An explicit
  reconnect may authenticate and adopt a valid replacement after that
  detection;
- a malformed authority/legacy keyfile, authentication, network,
  malformed-response, or any other error → stop and explain the error without
  server bodies or secrets; never reinterpret the result as an empty folder.

Folder detection itself is non-destructive. **First connection to an existing
root always requires replacement consent and a probe-verified safety backup:**
the first-connection prune set is the snapshot of every local profile, and an
initialized device always has at least one managing Admin, so that set is not
empty in v1. There is no vague “meaningful data” or nominal empty-set shortcut.
Creating a new root from this device's current graph does not replace local
data and therefore needs no replacement prompt. Later graph refreshes use the
separate graph-changed prompt. M3 implements configuration, wire formats,
lifecycle state, and marker verification/pinning for an already-committed
root, but it never publishes an empty root or manifest. M5 validates an
authentic bootstrap-bearing manifest and performs both new-root commit and
destructive graph adoption after all prerequisites exist.

**VERIFIED: `restoreDeviceGraph` is ADDITIVE, not a replace.**
`publishProfileGraphRestore`
(`lib/services/profiles/profile_registry.dart:3952`) activates the staged
profiles and inserts imported resources but never retires pre-existing
profiles — the file-restore dialog says outright "Existing profiles are not
overwritten". Adoption therefore is a **CircleAdoption flow**, not a bare
restore call:

1. **Adoption intent + pre-restore snapshot — FIRST, before restore
   (round-7):** durably persist to engine-owned prefs `{adoptionId,
   phase: restoring, preRestoreProfileIds: <every local profile ID right
   now>}`, and probe-verify (decrypt-check) the §6 safety backup before
   anything else runs. Round-6 still had a fatal window: restore committed
   and its own journal cleaned (`markRestoreCleaned` runs before
   `restoreDeviceGraph` even returns,
   `lib/services/profiles/profile_restore_coordinator.dart:506`), then a
   crash before the engine record landed left imported profiles active
   with NO map — and re-running join would duplicate the whole set
   (restore is additive). With the intent written first, recovery is
   mechanical and name-matching-free: **imported set = current profile IDs
   MINUS the snapshot** (nothing else creates profiles mid-flow); roll
   those back via the existing delete APIs and re-join cleanly. ("Keep the
   restore journal until adoption acknowledges" was evaluated and
   rejected: a retained `published` journal is removed idempotently by
   bootstrap — it cannot carry the mapping across the window.) The
   snapshot ALSO resolves a round-7 contradiction: invariant 1 said the
   prune set comes only from the engine's mapping, but at FIRST JOIN the
   pruned profiles are pre-circle and have no mapping — **the join prune
   set IS this snapshot, captured durably before restore**; a refresh
   prunes only mapped predecessors.
2. `restoreDeviceGraph` (existing, atomic, staged-publish)
3. **Durable adoption record (round-6):** advance the intent to
   `{phase: restored, circleProfileId ↔ newLocalId, circleResourceId ↔
   newLocalId, oldLocalId → newLocalId}`. This engine record is the ONLY
   journal spanning the adoption tail; each later step advances `phase` on
   completion, and a crash resumes idempotently from the recorded phase at
   next launch. This is a small phase record, not a journal framework.
   **Round-5 prerequisite stands:** extend `ProfileGraphRestoreReport`
   with the backupId → new-local-resource-ID map (`_allocateResourceIds`
   is private; the report today carries only profile IDs + counts) —
   without it these maps cannot be built, the next canonical export treats
   every resource as new, and step 5 has no remap targets. Small additive
   report change.
4. **DB copy-forward (round-3 fix; REFRESH PAIRS ONLY — round-8: first
   join has no pairs, the bootstrap carries the DBs):** for each mapped
   old→new profile pair,
   copy the old profile's database files into the new profile's storage.
   Restore stages DB sections into the NEW profile's scope, so a package
   without DB sections yields new profiles with EMPTY databases — without
   this step, the prune below deletes the only copy of favorites/history.
   Paths resolve per scope with no session switch
   (`ProfileRuntime.withCapturedScope`, `lib/services/debrify_tv_database.dart:87`).
   **Handle lifecycle (round-4/7):** a pair copies only after the source
   scope's DBs are deactivated + drained — `debrify_tv.db` via the
   scope-lock/drain machinery (`debrify_tv_database.dart:188-212`) AND the
   independently-managed, WAL-mode `iptv_catalog.db` via its own
   `IptvCatalogDb.closeScope()` (`lib/services/iptv_catalog_db.dart:834`;
   round-7 — it has its own handle lifecycle and had been left to the
   generic file walk) — and strictly before the target scope's first open;
   WAL/SHM sidecars are checkpointed or copied with the DB. **Placement is
   atomic and redo-safe (round-7):** each file copies to a temp name and
   renames into place; the phase record marks per-pair completion, so a
   crash mid-copy redoes that pair (the source still exists — prune hasn't
   run). (Round-7's "carry while the generation is invisible / publish a
   new verified generation" was evaluated and REJECTED as doctrine
   over-applied: `verifyGraphProfile` runs immediately BEFORE graph
   publication (`lib/services/profiles/profile_data_generation.dart:226`)
   and every `manifest_hash` reader is staging-side — nothing re-verifies
   a published generation, whose storage the app mutates on every ordinary
   write. Torn-copy atomicity is the real requirement.) Non-active pairs
   run steps 4–6 now; the formerly-active Admin's pair runs them in
   step 7, after the handoff closes its handles.
5. **Remap copied DB rows (round-5):** run the existing
   `ProfileDatabaseSnapshot.remapResourceReferences` on each copied target
   using old-local → new-local resource IDs (step 3's maps joined). Copied
   bytes carry OLD local resource IDs in playlist/history/ordering rows;
   restore minted new IDs and prune deletes the old ones — without the
   remap those rows dangle.
6. **Local-state carry-forward (round-6 — without it, every refresh, not
   just join, resets the user's device-local choices):** the prune's
   cleanup wipes every `p.<oldId>.g.*` preference and the whole
   `profiles/<oldId>` tree
   (`lib/services/profiles/profile_data_generation.dart:36`), while the
   sync payload deliberately omits device-local state
   (`lib/services/profiles/profile_preference_portability.dart:217`) — so
   DB copy-forward alone still loses the download-folder grant/paths,
   custom subtitle fonts, custom external-player commands, battery-opt
   status, and vault key source on every graph refresh. Before prune, copy
   old-scope → new-scope: (a) **ALL `p.<oldId>.g.*` preference keys
   (round-8 revision):** refresh packages carry NO preference sections at
   all (§1 D3), so carry-forward is the ONLY preference continuity at
   refresh — exactly as it is for DBs. Copy verbatim, then remap the
   resource-referencing keys (`webdav_servers_v1`, `iptv_playlists`,
   `stremio_addons_v1`, `indexer_manager_configs_v1`,
   `real_debrid_endpoint`) from old to new resource IDs via step 3's maps —
   restore's own `_normalizePreferenceValues` proves those embedded refs
   are enumerable, and carrying them un-remapped would resurrect dead
   resource refs. **A ref with no map entry (the resource was deleted
   circle-side) is DROPPED, matching restore's normalization — never
   carried dangling (round-9).** The hot merge that follows every graph apply then brings
   the portable keys up to date;
   (b) any `profiles/<oldId>` tree file restore did not stage (staged files
   win) — **EXCLUDING `*.db`, `-wal`, `-shm` and temp files (round-7):
   databases move only through step 4's drained, checkpointed copy; the
   generic file walk must never grab a live SQLite file or its sidecars.**
   Like step 4, this step runs for REFRESH pairs only — at first join
   there are no pairs, and pre-circle device state is deliberately NOT
   carried into unrelated circle profiles (that would be the banned
   identity merge; the joiner reconfigures device-local bits like the
   download folder once).
7. **Session handoff** onto the imported Admin (the graph always contains
   one — `_assertAdminInvariant`), then run steps 4–6 for the
   formerly-active profile's pair (its handles are now closed). **Target
   open-gate (round-7 — the sharpest hole in the round-6 ordering):** at
   this point the COPY TARGET is the freshly-activated Admin, whose
   services would immediately open its still-empty `debrify_tv.db` /
   `iptv_catalog.db` — and copying over an open SQLite file corrupts it.
   The flow therefore holds the target scope's DBs closed (scope lock;
   the adoption progress screen is already full-screen and stays up)
   until this pair's copy + remap complete — service activation that
   touches either DB defers behind the gate.
8. **Prune superseded local profiles — LAST, with MODE-SCOPED guards
   (round-8; the round-7 wording applied the pair guard at join, where no
   pairs exist and manufacturing them would be the banned identity
   merge):** a **refresh** prunes only mapped predecessors, each gated on
   its pair's copy-forward + remap + carry-forward having succeeded; a
   **first join** prunes exactly the step-1 snapshot, gated on the
   probe-verified safety backup + successful bootstrap restore + completed
   handoff — pre-circle profiles get NO copy/carry, their data is
   deliberately discarded with consent, and the safety backup is the
   escape hatch. Both modes run through the EXISTING per-profile delete
   APIs (each with its cleanup ledger) — never anything else, and never by
   name.
   **Prune pre-steps (round-5/6):** `createProfile` auto-seeds every new
   profile with `defaultSeed` grants to EXISTING shareable resources
   (`lib/services/profiles/profile_registry.dart:933`/`:1757`), and
   `deleteProfileWithDisposition` refuses under several conditions (active
   profile, active jobs, admin invariant, borrowers, artifacts). Per old
   profile: revoke **ALL grants other profiles hold on its owned
   resources** — the borrower guard counts ANY grant, not just the
   auto-seeded ones (`:1650`) — then delete with
   `deleteOwnedResources: true` AND `detachPublicArtifacts: true`
   (`owned_artifacts` rows otherwise refuse the delete — `:1680`),
   recapturing authorization between steps. On refusal: park it
   **prune-pending**, retried next Admin cycle. **Containment (round-6):
   while ANY profile is prune-pending, graph pushes are BLOCKED outright**
   — `exportAllProfiles` exports every profile including disabled ones
   (`lib/services/profiles/profile_package_service.dart:194`), so the
   round-5 rule of merely withholding circle IDs contained nothing: the
   leftover's records would still ride along in the package. Hot docs keep
   flowing; the status card names the blocking profile.

The prune tail is deliberately non-atomic: a failure leaves a visible,
re-prunable profile — benign locally, and contained circle-wide by the
graph-push block above — rather than risking data loss inside a new
registry transaction. `ProfileDeviceResetService` was evaluated and
rejected: it factory-resets device identity and would wipe the sync
provisioning itself.

**Identity mapping (round-3 corrections):** profile IDs are random per
device and every restore mints new ones
(`lib/services/profiles/profile_restore_coordinator.dart:139`), so the engine
keeps a device-local **circleProfileId ↔ localProfileId map** (engine-owned
prefs, not a registry schema change). **Every pusher — not only the seeder —
mints and persists a circle ID for any still-unmapped local profile before
exporting** (a newly created profile on any enrolled device gets one on its
next push). The same applies to connection resources: pushers mint **circle
resource IDs**, because `exportAllProfiles` embeds random local
`resource.id`s and restore re-allocates them — without stable circle IDs,
every post-adoption rebuild would look dirty (see §3 canonicalization).
Every graph revision travels with the authenticated
`backupId → circleProfileId` and `localResourceId → circleResourceId` maps
in the pusher's manifest — correlation never relies on list order across
revisions. Within one restore, the joiner correlates
`ProfileGraphRestoreReport.importedProfileIds` to `package.profiles` order
(assert this correspondence in a test). Registry schema stays at **v6** (the
current version, `lib/services/profiles/profile_registry.dart:23` — round-6
corrected the stale "v5" here; the point is unchanged: NO schema bump, zero
migration risk).

### D3 — Two tiers, because the data has two temperaments
- **Hot document** (KBs, changes constantly, conflicts are NORMAL): per-profile
  portable preferences. Merged automatically, per-record where it matters.
  This is the daily value: resume everywhere, settings follow you.
- **Graph** (MBs, changes rarely, conflicts are RARE): registry graph +
  per-profile preferences + avatars/portable files. v1 applies it
  **prompted**, because graph apply replaces and consent is cheaper and
  safer than building per-category set-reconcile now (that's v2).
  (Handler-based additive refresh was considered as an alternative to
  adopt-style refresh and rejected for v1: it fragments into per-category
  paths, cannot carry profile create/rename/PIN ops, and still needs the
  adoption flow for join.)

**Refresh graphs are STRUCTURE-ONLY (round-8 upgraded this from
"DB snapshots are bootstrap-only").** `debrify_tv.db` is, per its own
header, "favorites/history/resume bookkeeping" — mutable daily data that
would make the graph permanently dirty and turn every favorite toggle into
a destructive prompt. So: the **bootstrap section carries everything**;
**refresh packages exclude DB snapshots** via a small additive
`includeDatabases: false` on `exportAllProfiles` (packages without DB
sections are already valid by construction — `exportProfile` emits them
conditionally) — **AND (round-8) exclude the per-profile preference
sections entirely** (additive `includePreferences: false`). Dropping DB
snapshots alone was only half the fix: `exportAllProfiles` embeds every
portable preference, so every episode watched, playlist edit, or settings
tweak still restamped the graph's semantic digest — the 6-hour rebuild
would have minted a new PROMPTED revision after every evening of use, for
state the hot tier already owns. With preferences out of the refresh
payload (not merely out of the digest), a refresh apply also can NEVER
clobber hot state or device-local execution data with stale embedded
copies. The refresh graph digest now changes only on STRUCTURAL edits —
profile create/rename/PIN/policy, resource add/remove, avatar — which is
exactly what the prompted-refresh consent is for. Local continuity across
refreshes comes from the carry-forward steps in D2 (DBs AND preferences,
symmetric), NOT from the restore path. The bootstrap is
**regenerated whenever the circle's profile set changes**, on manual full
push, and — round-6, so a joiner doesn't inherit a months-stale library —
**at most daily when the DB files' content has changed** since the last
bootstrap (checked during an Admin-session cycle, off the graph cadence).
A later join therefore never restores a profile set that no longer exists
nor a badly stale snapshot while a publishing Admin device is active. Calendar
age alone does not invalidate the recovery base: §5 explicitly permits a
30+ day dormant bootstrap when it is the newest complete one, then repairs it
immediately with eligible graph/hot/tombstone state. **Join flow = adopt
bootstrap → immediately auto-apply the latest eligible graph revision (with
copy-forward) → hot merge** — never a stale bootstrap alone. Ongoing
channel/favorites DB sync is v2 scope.

The trick that makes most hot merge cheap: concurrent-edit records **already
have intrinsic timestamps** — `playback_state_v1` entries carry `updatedAt`
(LWW resolution already exists at `lib/services/storage_service.dart:3407`),
and `SeriesSource` carries `boundAt`. The original design assumed scalar
settings did not conflict in practice and gave the entire scalar map one
stamp. The physical Koofr failure above disproved that assumption: changing
or rebuilding any scalar can lend fresh provenance to every stale scalar in
the map. §13 therefore adds per-setting provenance; no ordinary setting may
win merely because another key changed on the same device.

---

## 2. What we reuse verbatim (verified)

| Machinery | Where | Role in sync |
| --- | --- | --- |
| Full-state export | `lib/services/profiles/profile_package_service.dart:181` `exportAllProfiles` (+ additive `includeDatabases` / `includePreferences` flags — refresh graphs pass both false, §1 D3) | graph push payload |
| Atomic graph apply (ADDITIVE — see D2) | `lib/services/profiles/profile_restore_coordinator.dart:80` `restoreDeviceGraph` (staged publish, ghost-purge rearm at `:138`) + existing per-profile delete APIs as the prune companion | CircleAdoption flow |
| Encrypted envelope | `lib/services/profiles/portable_profile_package.dart:534` Argon2id(19MB, it=2 — sub-second) + AES-GCM, off-isolate, `probeFile`/`decryptFile` | at-rest crypto, reused as-is for the graph; small additive `sealSyncDocument`/`openSyncDocument` for hot docs using the same primitives + own AAD, but with a **circle-fixed KDF salt** (stored in `circle.json`) + per-file random AEAD nonces, so the key derives ONCE per cycle — the stock format's per-file random salt would force one 19MB Argon2id run per peer × section on every pull, colliding with the tvOS low-memory gate |
| Pref portability policy | `lib/services/profiles/profile_preference_portability.dart` | hot doc contents = `_exportPreferences` output — which is **private today** (`lib/services/profiles/profile_package_service.dart:387`); expose it additively (round-7). **Null rule (round-7):** `prepareValue` deliberately exports device-sealed IPTV execution state and malformed blobs as EXPLICIT NULLS (`profile_preference_portability.dart:51`) so a one-shot RESTORE clears them — but a recurring merge honoring nulls would erase local device state every cycle. The doc builder therefore DROPS null-valued entries; hot deletion travels only as tombstones |
| WebDAV client (protocol layer only) | `lib/services/webdav_service.dart` (PROPFIND, DELETE, basic auth) | transport; only PUT/MKCOL/GET-bytes are new. **NOT reused: `_authorize`** — it gates on the ACTIVE profile's `ProfileFeature.cloud` grant, which would break sync under non-admin/kid sessions. The engine holds its OWN device-level transport credentials (§5) |
| Credential storage | **`DeviceKeyProvider` (round-7 — supersedes round-6's SecretVault choice, which was WRONG):** the repo already ships a platform-native secret store — the `debrify/device_secret` channel backed by Android Keystore AEAD (`android/.../security/DeviceSecretCipherPlugin.kt`), Apple Keychain including a tvOS implementation (`tvos/Runner/AppDelegate.swift`), Windows DPAPI (`windows/runner/flutter_window.cpp:105`), and a Linux passphrase-wrapped vault (`lib/services/profiles/device_key_provider.dart:10`). The connection-resource secrets inside the very graph packages sync ships are ALREADY sealed with it; `SecretVault`'s "OS keystores unavailable" header is stale in scope | engine transport credentials + the machine-generated sync secret copied from `circle.authority` and sealed via `DeviceKeyProvider.cipher` with sync-specific AAD. Two encoded caveats: the **Linux vault can be LOCKED** — the cycle defers until unlock, exactly as profile resources already do; and sealed values are **device-bound, non-exportable**. Runtime cycles use this sealed copy while pinning the exact authority bytes. `SecretVault` (obfuscation-grade, `lib/services/secret_vault.dart:12`) is NOT used for sync secrets |
| Single-flight + scope-capture patterns | remote fast path (`_applyingRemotePayload` guard, captured authorization) | engine concurrency discipline |
| Admin authorization for graph ops | remote receiver's pattern for `ConfigCommand.profileGraph` (`lib/services/remote_control/remote_command_router.dart:1088`) | graph build/apply authorization |

**Not reusable (verified):** there is no stable per-install device ID —
`RemoteControlState._generateDeviceId` regenerates per start
(`:206`/`:305`) and `SecretVault`'s hardware ID is private to the vault.
The engine **mints and persists its own sync device UUID** when a sync account
binding is enabled.

---

## 3. Server layout — dumb-server-proof by construction

```
<effective endpoint>/Debrify/debrify-sync/
  circle.authority                    # sole LWW authority, JSON v1:
                                      #   sealed marker bytes + sync secret
  devices/<deviceId>/manifest.enc     # THE commit record: clockOffsetMs vs server
                                      #   Date + circleId maps (profiles+resources)
                                      #   for the current graph revision + this
                                      #   device's graph SCHEMA CLAIM (ratchet
                                      #   input, §5) + list of {section,
                                      #   contentHash, semanticDigest, updatedAt,
                                      #   schemaVersion, size}
  devices/<deviceId>/sections/<contentHash>.enc   # immutable, content-addressed blobs
```

Automatic pre-adoption safety backups are local, not part of this server
layout. They are written under app support in
`webdav-sync/pre-join-backups/`, encrypted with the sealed circle-key secret,
and are
never synced. The same bounded database fallback applies when a full package
cannot fit: IPTV caches rebuild and omitted Debrify TV channels are not part
of that recovery point. On physical tvOS, app support maps to purgeable
Caches, so this is a verified transaction recovery point rather than a
permanent archive; users still need normal M2 WebDAV backups for durable
recovery.

This layout is deliberately hidden implementation detail. Signing into the
same effective WebDAV endpoint is sufficient to discover the fixed `Debrify`
folder; users do not browse into `debrify-sync/` or copy IDs between devices.

**The single authority object is committed LAST, never first.** New-folder activation in
M5 is one ordered operation:

1. Ensure and PROPFIND-verify the `debrify-sync` collection. PUT a random
   sentinel, GET it immediately, and require exact bytes; DELETE is
   best-effort. This proves the linearizable read-after-write behavior the
   authority register requires. Conditional-create behavior is irrelevant.
2. Read `circle.authority`. A present strict/authentic object is joined; a
   malformed object fails closed; only 404 permits initialization.
3. Generate the secret, unchanged sealed root marker, root metadata/key, and
   profile/resource circle IDs locally, then wrap marker+secret in one bounded
   version-one authority object.
4. Build, seal, upload, and hash-verify the initial `bootstrap`, `graph`, and
   hot/tombstone sections.
5. Upload the seed device's manifest last and read-back verify it.
6. Reconfirm the authority is a definitive 404, PUT `circle.authority`, then
   always GET it. `If-None-Match: *` may be sent but is only opportunistic. A
   2xx is never ownership proof. Exact read-back finishes this candidate;
   different valid bytes are the winner and atomically drive secret adoption,
   candidate identity/state reset, orphan cleanup, and existing-root adoption.
   Malformed or absent read-back fails closed. The accepted authority bytes
   are pinned locally exactly.

Until step 6 succeeds, uploaded device objects are uncommitted orphans and no
client may treat the folder as a sync set. A peer directory participates only
when its manifest authenticates under the pinned root key and declares the
same circle ID; pre-root/racing or malicious directories are ignored with a
privacy-log diagnostic. If another authority wins concurrently, this initializer
abandons its candidate root, cleans its own orphan directory when safe, and
follows the existing-root path. If the app crashes before step 6, the folder
still has no committed root and a later attempt may initialize it. The
candidate device ID is persisted before upload and reused on retry, so one
device does not create a fresh orphan on every attempt; when that initializer
returns, it cleans only its own losing/cancelled candidate directory. If it
never returns, the unauthenticatable directory is accepted v1 server litter
and remains ignored. No other device garbage-collects it: cross-device delete
based on an authentication failure would violate per-device ownership and
amplify a malicious/corrupt server response into data loss. Conversely, a
committed marker with no authentic, complete bootstrap-bearing manifest is
corrupt or incomplete and fails loudly—another device never silently seeds
it. **An empty manifest is never published.**

**M3 freezes the root wire format before M4/M5 depend on it.** The bounded
outer envelope exposes only the canonical format/version plus Argon2id
algorithm, salt, and bounded parameters needed to derive the key; that entire
header is included in AEAD AAD. The encrypted body contains the circle ID,
created-at, schema floor, and key-check. Section/manifest AAD remains generic
but binds root/circle ID, deviceId, logical section name, and schema version.
M3 ships golden-vector, wrong-key, tamper, unsafe-KDF-bound, and
forward-version rejection tests for this format; later milestones may add
section schemas without changing the immutable root envelope.

- **Each device writes only its own directory.** No cross-device write
  conflicts exist, on any server, with any (broken) ETag semantics.
- **Sections are content-addressed and immutable.** A push uploads new blobs
  first, then overwrites the small manifest last. Readers trust only what a
  manifest references and verify the hash after download. Torn/partial pushes
  are therefore invisible; the previous manifest keeps working mid-push.
- Old unreferenced blobs are GC'd by their own device after 7 days.
- Sections: `graph` (refresh form: STRUCTURE-ONLY — no DB snapshots, no
  preference sections, §1 D3) + `bootstrap` (full package with everything —
  regenerated at seed, on manual full push, whenever the profile set
  changes, and at most daily when DB content changed, §1 D3) +
  `hot/<circleProfileId>` (two sub-parts, see §4) +
  `tombstones/<circleProfileId>`.
- Pull cost: 1 GET per peer manifest + only changed sections.

**Dirty detection is zero-touch, SEMANTIC, and CANONICALIZED:** the digest
is computed over the **canonical plaintext**: stable key order, `createdAt`
and all envelope metadata excluded, and — critically — **every local
profile/resource ID (and embedded reference to one) rewritten to its circle
ID** before hashing. Without ID canonicalization, every post-adoption
rebuild differs (restore re-allocates local IDs) and devices ping-pong
no-op graph revisions forever. Rewriting embedded references is mechanical:
restore already remaps them (`remapResourceReferences`,
`_normalizePreferenceValues`), proving they are enumerable. The engine
rebuilds a section, computes the semantic digest, and only seals + pushes
when it differs from the device's own **last-PUSHED** digest. No mutation
hooks anywhere (the tombstone helpers in §4 are the sole exception).
**Round-6 — the round-3 "adopted-digest echo-kill" is REMOVED; it defeated
anti-entropy:** suppressing pushes of adopted state meant a record could
live in only its original author's directory forever. When that device went
stale at 30 days, no surviving manifest carried the state, and a new joiner
could never receive it — the same hole round-5 had already patched for
tombstones but not for records. Instead every device **publishes its full
merged union**, and convergence, not suppression, ends the traffic: merge
is a join (union + LWW over timestamps that verbatim apply and
normalized-time publishing preserve exactly), serialization is canonical —
so once devices hold the same state, each rebuild is digest-identical to
that device's last push and no push fires. Bonus: any single non-stale
device's doc is a complete hot bootstrap for a joiner.

**Threat model:** §15 intentionally places the at-rest encryption secret beside
the data. Encryption therefore no longer protects confidentiality from the
storage provider or an attacker who can read the whole sync folder. AEAD still
authenticates every file, defends against isolated cross-folder/blob leakage,
and preserves the stable inner-marker wire format and AAD
bindings (deviceId + section name + schemaVersion). The server is trusted for
availability and
— documented, bounded in BOTH directions (round-6) — for **time** (§4.4):
future-stamped records clamp at publish time, and the server's `Date` is
held to a per-device monotonic high-water mark, so neither a forward-lying
nor a backward-jumping server clock can bury genuine edits. Version vectors
deferred to v2 unless practice proves this insufficient. Server-side
rollback of a peer's manifest is detected cheaply: remember each peer's
last-seen manifest timestamp, ignore regressions, log to privacy log.
Transport: Basic credentials go only to the selected server origin — the sync
client never follows cross-origin or scheme-downgrade redirects (M1), and
explicit `http://` endpoints are permitted but labeled insecure in the Custom
sync login as well as the normal WebDAV configuration and Migrate flows.

---

## 4. Merge semantics (the one new module — pure Dart, exhaustively unit-testable)

**Milestone boundary:** M4 implements this module and its engine integration
against an injected root context plus authenticated profile AND resource maps
(`circleProfileId ↔ localProfileId`, `circleResourceId ↔ localResourceId`).
Both maps are required inputs: absence means inactive/no-op, never “use a
local ID temporarily.” M4's
integration tests use fixtures, but no production pull/apply/push trigger is
armed until M5 creates or restores the real maps and activates the binding.
M5 may invoke the builders explicitly inside its bounded seed/adoption
transaction before activation; that is not a scheduled M4 cycle. This order
is intentional because M5's graph adoption must finish with the hot merge
already available.

The hot doc has two independent semantic domains (round-3 fix): `scalars`
and `watchState`. `watchState` retains its section digest/stamp plus its
record stamps. **After §13, every scalar entry also carries its own stamp;
the outer scalar digest is dirty-detection/integrity metadata only and never
arbitrates a key.** The implemented legacy-v1 shape gives the whole scalar
map one `updatedAt`. Splitting it from playback prevented a playback write
from restamping settings, but did not prevent setting A (or a reconstructed
local scalar map) from restamping stale setting B. That narrower failure was
confirmed on physical devices and §13 supersedes the whole-scalar rule.
**Cycle order remains pull → merge → apply → push**, so a device always
merges the world before publishing.

Given local state + all peers' hot docs for a profile:

1. **Scalars: per-key LWW with key-union (§13).** Every portable scalar is
   `{value, stamp}`. An unchanged key preserves its exact normalized time and
   origin across rebuilds/rebroadcasts; only a locally changed key receives a
   new stamp. Winner for each key is the deterministic total order already
   used elsewhere: `(normalizedTime, originDeviceId, valueHash)`. Keys absent
   from one doc remain eligible from another, protecting new-in-schema keys.
   Two devices genuinely editing the same setting resolve newest-per-key;
   editing different settings unions both changes. A whole-map digest change
   can trigger publication but can never transfer freshness between keys.
   **Null rule (round-7): docs never carry nulls** — the builder drops
   null-valued entries at build (§2 pref-portability row explains why they
   exist at all), and apply NEVER removes a key because a doc nulls or
   omits it. Hot deletion travels only as tombstones.
2. **Watch state: deep-merged regardless of winner** (union across ALL docs +
   local, per-record LWW by intrinsic timestamp):
   - `playback_state_v1` — per record-key / episode-coordinate by
     `updatedAt` (feeds the resume reconciler as ordinary local state —
     reconciler + Trakt/Simkl remain authoritative above it). **Round-6 —
     the store is ALIAS-KEYED and NESTED:** the same episode can exist
     under an IMDb-keyed record AND a release-title-keyed record, and the
     read path unions them per episode coordinate at query time
     (`getMergedEpisodeProgress`, `lib/services/storage_service.dart:3393`).
     The merge therefore mirrors that shape exactly: top-level keys are
     distinct records (aliases are NEVER collapsed — that stays the read
     path's job), and within a series record, episode coordinates merge
     individually by `updatedAt` — never whole-value LWW on a series
     record, which would revert sibling episodes' progress
   - `continue_watching_v1` — same; after union, re-sort by `updatedAt` and
     re-apply the app's 50-item cap (`lib/services/storage_service.dart:2536`)
     so recency, not insertion order, decides who survives an N-device union
   - `series_source_*` — per imdbId by `boundAt`; within a title union by
     **`bindingKey`** (the identity `addSource` actually dedups by — NOT
     torrentHash: hashless provider-native cloud bindings are a first-class
     state and a hash union would collapse them all). **Per-title ORDER is
     its own LWW value (round-5):** `setSources` reorders without touching
     any `boundAt` and the first source is semantically preferred, so the
     engine diff-stamps order changes against its last snapshot
     (`orderChangedAt`) and the doc carries `{order: [bindingKey…],
     orderStamp}` per title; the newest order wins, unioned extras append
     by `boundAt`
   - **Local completion sets:** `finished_movies_v1`,
     `explicitly_watched_series_v1`, local episode completion — set union
     per title/episode with tombstones. These lists are **timestamp-free
     strings** (`:2573`), so the engine **diff-stamps additions**: each
     cycle it compares the current membership against its last-synced
     snapshot and records `firstSeenAt` for new members in engine-owned
     state (no schema change, no hooks). Removals get precise stamps from
     the hooked helpers below. Rewatch-after-unwatch is therefore
     well-ordered: a fresh membership with `firstSeenAt` newer than the
     tombstone wins; an unchanged membership never beats a tombstone.
   - **Playlists (round-8):** `user_playlist_v1` + `playlist_favorites_v1`
     were promised as hot data (§1 goal) but had silently fallen to
     whole-section scalar LWW — two devices editing playlists before
     exchanging pushes would drop one side's collection wholesale, and a
     removed favorite could resurrect under an unrelated newer scalar win.
     They join the union machinery instead: per-item identity =
     `computePlaylistDedupeKey` (`lib/services/storage_service.dart:4236`
     — provider-aware, already the app's own dedup identity), additions
     engine-diff-stamped against the last snapshot (items are
     timestamp-free, same treatment as the completion sets), removals
     tombstoned through the audited helpers (the M4 audit scope extends to
     every playlist/favorites mutator, including the clears at
     `:4441`/`:4448`), and each list's ORDER is its own diff-stamped LWW
     value exactly like per-title source order.

   **Lossy-twin rule (round-8):** hot docs carry the PORTABLE projection —
   execution fields (`url`, `localpath`, `headers`, …) are stripped at
   build (`lib/services/profiles/profile_preference_portability.dart:170`)
   — so a device's own record returns from peers' round-6 union
   rebroadcasts stripped but IDENTICALLY stamped, and the hash tie-break
   could let the stripped twin beat the local original, erasing resume
   execution data for no reason. Record EQUALITY is therefore judged on
   the portable projection: if the local record's projection equals the
   doc record, they are the SAME record and the local (richer) copy wins;
   LWW engages only when projections differ. A genuinely NEWER peer record
   replacing local execution fields is correct behavior — the position
   moved on another device and this app re-resolves sources by design.
3. **Tombstones — the ONLY mutation hooks in the plan, routed through
   central helpers:** every deletion path records `{key, removedAt}` in a
   small engine-owned pref (write-side only, per the ghost-rows invariant:
   never a read-side filter). Verified paths that must route through the
   helpers — sources: `removeSourceByHash`/`:213`, `removeSourceEntry`/`:228`,
   `removeAllSources`/`:243`, `setSources`/`:249` (keyed imdbId+bindingKey);
   playback/completion: CW removal, `clearContinueWatching` (round-6),
   `clearPlaybackStateByImdbId`/`:2672`, `unmarkMovieAsFinished` (round-6),
   `unmarkEpisodeAsFinished`/`:2827`,
   `setSeriesExplicitlyWatched(watched: false)` +
   `LocalSeriesCompletionService.clearCompletedHistory` (round-6),
   `clearAllPlaybackData`/`:3830`, `clearPlaylistProgress`/`:3848`. Bulk
   clears emit per-record tombstones for what they removed — never a
   "clear all" marker. **This list is illustrative, NOT normative — round-6
   caught it incomplete.** The normative source is M4's audit: it
   enumerates every removal API in `storage_service.dart` +
   `series_source_service.dart` + the watched-action fan-out BEFORE any
   helper lands, and ships a test asserting the audited set matches the
   helper call sites. Merge: a record loses to a newer tombstone; retention
   per §5.
4. **Clock sanity (round-5 revision — docs are published in NORMALIZED
   time):** per-record `updatedAt`/`boundAt` are stamped by existing
   writers with the LOCAL clock and never pass through the engine. Each
   device measures `clockOffsetMs` against the WebDAV server's `Date`
   header each cycle — **the full measured offset, always applied**
   (publishing zero for an out-of-bound clock would leave a day-ahead RTC
   dominating every comparison). Hot docs always carry **server-normalized
   timestamps**: at doc build, only records the last-synced snapshot shows
   as locally changed get normalized with the device's CURRENT offset;
   records adopted from peers keep their already-normalized stamps
   untouched. This preserves timestamp ORIGIN across rebroadcasts — round-4's
   verbatim apply meant an adopted record would otherwise be re-adjusted
   under the adopter's offset on its next publish, letting skew make stale
   records or tombstones beat genuinely newer updates. At merge, only RAW
   LOCAL state is offset-adjusted; doc records are used as-is. **Round-6 —
   ordering must be bounded AND deterministic; three revisions:**
   (a) **Future-clamping moves to PUBLISH time** — the builder clamps any
   record it is normalizing that lands in the future to its current
   server-normalized now, so every receiver sees identical stamps.
   (Merge-time clamping produced a different clamped value per receiver —
   divergent winners that could never reconverge. Merge-time clamping now
   applies only to raw LOCAL not-yet-published records.)
   (b) The server's `Date` is held to a persisted per-device **monotonic
   high-water mark**: a backward jump beyond 1h pauses publishing with a
   "server clock moved backwards" status warning instead of stamping under
   the regressed clock. The old claim that a lying server "shifts ordering
   only within the window of real record ages" was only true for FORWARD
   lies — a server reporting last year would back-date every local edit
   into oblivion. ("Pause on any large offset" was rejected: a device with
   a genuinely wrong RTC is exactly what the offset machinery exists to
   serve; §3's manifest-regression check covers content rollback, this
   covers time rollback.)
   (c) LWW uses the deterministic total order **(normalizedTime,
   originDeviceId, recordContentHash)** — each record carries `origin`
   (the deviceId that stamped its normalization, preserved verbatim ever
   after), so equal-stamp conflicts resolve identically on every device.
   (d) **Offset-delta damping (round-7):** a transient forward lie (one
   `Date: 2099` response) must not mint permanent-winner stamps — and
   under (b) alone it would ALSO wedge publishing forever once the server
   recovered ("backward jump"). A measured offset differing from the
   last-ACCEPTED offset by more than 24h is an outlier: that cycle neither
   stamps, publishes, nor advances the high-water mark, and the new offset
   is accepted only once it repeats on consecutive cycles. A genuinely
   re-set RTC or fresh sync-account setup passes immediately or within two
   cycles;
   a one-off server glitch never poisons a single stamp.
   A device measuring |offset| > 24h still shows the "check this device's
   clock" warning in the status card.

Applying merged hot state (round-4 fix — apply is VERBATIM):
- ALL profiles, active included → **scope-captured `ProfilePreferences`
  setters** (round-5: raw physical SharedPreferences writes would bypass
  `_write` entirely). **Round-6 correction to round-5's claim:**
  captured-scope writes DO run the tvOS recovery checkpoint, but they
  deliberately SKIP the native projection — `_write` publishes it only when
  `_capturedAccess == null`
  (`lib/services/profiles/profile_preferences.dart:346`). **Round-7
  sharpens this into ONE small additive API: a scope-captured BATCH apply**
  that validates entries, writes them in one pass, runs ONE tvOS recovery
  checkpoint (the per-key setters checkpoint on EVERY write — `:360` — so
  a 50-key apply would hammer the Keychain 50 times), and then, for the
  ACTIVE profile only, publishes the native projection once and pokes the
  pref-backed caches. **Pending-apply guard (round-8 — reversing round-7's
  "no journal needed", which was wrong for the diff-stamped layers):**
  pure LWW values do re-merge harmlessly after a crash, but a half-applied
  adopted completion-set member looks like a LOCAL addition next cycle —
  diff-stamping mints it a fresh `firstSeenAt` that can beat a peer's
  tombstone, resurrecting a deletion under a counterfeit stamp; adopted
  timestamped records would likewise be re-normalized as "locally
  changed", violating the round-5 origin rule. So the engine persists the
  merged target (KBs, engine-owned file) plus a `pendingApply` flag BEFORE
  the batch write; on the next cycle or startup with the flag set, it
  re-applies the target VERBATIM before any diffing or normalization runs,
  then clears the flag. Snapshot state advances only after a completed
  apply. The prefs layer never
  restamps — record timestamps live inside the JSON values, so verbatim is
  preserved. Read `visibleDataGeneration` fresh from the registry at apply
  time. NEVER apply through the mutation FACADES above prefs —
  `saveContinueWatchingItem` and the playback-state savers restamp
  `updatedAt: DateTime.now()`, which would corrupt record provenance and
  keep every rebuild permanently divergent from the last-pushed digest —
  no-op push traffic forever.
- After applying to the ACTIVE profile, poke the existing revision
  notifiers (e.g. `localCompletionRevision`) so UI/caches re-read —
  refresh signals only, never data rewrites.
- **CW cap-drops are NOT deletions**: when the merged top-50 pushes a
  record out, it gets NO tombstone — a cap-drop tombstone would actively
  delete history circle-wide; an un-capped record simply resurfaces if its
  recency ever earns a slot again.
- Accepted quirk: a pref explicitly `remove()`d locally can be re-filled
  from a peer's doc by the §4.1 key-union (this codebase overwhelmingly
  resets prefs by writing defaults, not removing keys).
- Authorization captured at read; a mid-apply profile switch aborts the
  remainder (house pattern).

**Invariant: every graph apply is immediately followed by a hot pull+merge.**
Round-8 demoted this from load-bearing to belt-and-suspenders for
REFRESHES (structure-only refresh graphs carry no preferences to be stale),
but it remains load-bearing at JOIN: the bootstrap's embedded preferences
may trail peers' hot docs, and the join's first hot merge repairs that
automatically.

---

## 5. The sync engine

Device-wide service (not profile-scoped), flag-gated (`webdav_sync_enabled`),
single-flight, serialized **pull→merge→apply→push** cycle. Identified by its
own minted-and-persisted **per-root-binding** sync device UUID (see §2 — no
existing ID is stable).

**Lifecycle is explicit and persisted:** `unconfigured` → `configured`
(normalized endpoint/folder + sealed secrets) → either `awaitingSeedCommit`
(definitive 404 with no prior pin) or `rootVerified` (matching authenticated
marker) → `awaitingAdoption` when the existing graph needs local mapping or
prune consent → `active`; any stage may enter `error` without pretending to
sync. Only `active` may schedule ordinary M4 cycles or display “Last synced”.
The only pre-active data mutations are M5's bounded activation transaction:
seed sections/manifest/root-last writes for a new folder, or the explicitly
consented adoption apply for an existing one. M3 implements these states and
existing-root marker verification, but cannot transition a new or unmapped
binding to `active`. M4 implements the ordinary cycle behind this gate. M5
validates peer/bootstrap data, performs seed commit/adoption, establishes the
identity maps, and owns the transition to `active`.

All root-specific state is namespaced by the authenticated circle ID: marker
pin, per-root device UUID, profile/resource maps, last-pushed digests,
tombstones, peer/clock high-water marks, schema ratchet, declined revisions,
and pending apply/adoption records. Before a marker exists, candidate state is
isolated by a fingerprint of the normalized endpoint + folder and is never
mixed into an active namespace. **Change WebDAV sync account** stages and validates a
new isolated binding while the old cycle is paused, then switches the active
pointer only after M5 completes seed/adoption. It never carries old root state
into the new folder and never deletes the old server data; an inactive old
namespace may be retained for an explicit return, but its former `active`
state is not trusted after local adoption into another root. Returning first
revalidates the marker and every mapped local profile/resource target; missing
or changed targets go through `awaitingAdoption` again. Updating only the
WebDAV password changes transport credentials inside the same binding and
does not reset sync identity.

**Transport authority is engine-owned (round-3 fix):** when sync is enabled,
the engine copies the dedicated WebDAV endpoint + credentials into
device-level sealed storage (`DeviceKeyProvider`, §2 — round-7) and performs
all sync HTTP with them directly.
It never runs `WebDavService._authorize` — that path gates on the ACTIVE
profile's `ProfileFeature.cloud` grant and would break sync whenever a kid
or ungranted profile is active. Profile-facing WebDAV features are
untouched. Hot sync therefore genuinely runs under any session. If the
user later rotates the server password, the engine's copy goes stale —
the status card surfaces a "re-enter server password" action rather than
failing silently. `clockOffsetMs` is (re)measured from the first server
response of each cycle.

**Legacy-transfer guard (round-4):** the shipped phone→TV remote graph
transfer is ADDITIVE — profiles it creates land outside the circle
mapping, and the next Admin push would mint circle IDs for them and
propagate the duplicated set circle-wide. On sync-enabled devices an
incoming legacy graph transfer raises a warning naming that consequence
and recommending WebDAV Sync instead.

M4 implements these triggers: app launch (post-unlock), foreground, playback
stop (hot push), app background (hot push), every 15 min while active, manual
"Sync now". They remain unarmed until M5 establishes mappings and transitions
the binding to `active`. Debounce 45s. Suppressed during active playback on TV
and under the tvOS low-memory gate. Graph section rebuild at most every 6h or
on manual sync — hot docs are the frequent traffic (and with DB snapshots AND
preference sections both out of the refresh graph — §1 D3, rounds 2+8 —
ordinary watching, favoriting, and settings tweaks never dirty it).

**Graph revision arbitration:** the winning graph is the newest by the
**graph SECTION's own `updatedAt`** from each manifest's section list
(deviceId tiebreak) — same LWW rule as everything else — **among revisions
at the circle's schema ratchet**. NEVER by the manifest's overall
timestamp (round-7): manifests refresh on every hot push, so a chatty
device would promote its months-old graph over a newer one. The manifest
timestamp is the device's HEARTBEAT and feeds only the 30-day staleness
cutoff.
The ratchet is **DERIVED, never stored centrally** (round-5: a mutable
ratchet in the shared `circle.json` would need cross-device overwrites —
exactly what this layout forbids, and concurrent bumps could let the lower
writer win on broken-ETag servers): each manifest carries its device's
published graph schema claim; the effective ratchet = max over non-stale
manifests' claims, and each device persists the max it has ever seen
monotonically (never lowered, even if the claiming manifest later goes
stale). Devices never apply a revision below the ratchet (round-3 fix:
during a
rolling upgrade, an older device's lower-schema graph with a newer
timestamp must not win and drop fields it cannot represent). A
below-ratchet device keeps hot sync and shows "update this app to change
profiles & connections". Concurrent Admin edits on two devices before a
pull = the older one loses and is lost (documented v1 trade; set-reconcile
in v2 removes it). **Declined revisions persist**: the engine stores the
declined revision's semantic digest and never re-prompts for it — only a
genuinely new revision prompts again.

**Admin gating (graph tier only):** `exportAllProfiles` AND
`restoreDeviceGraph` both hard-require an Admin actor with manageProfiles +
backupRestore — so the engine builds/pushes the graph section and shows
graph-apply prompts **only while an Admin profile session is active**. Under
a non-admin session the cycle runs hot-docs-only and the status card shows
"Profiles & connections sync waits for an Admin session". **Graph pushes
are also blocked while any profile is prune-pending (§1 D2 step 8,
round-6)** — hot docs keep flowing; the card names the blocker.
**Adoption-in-flight blocks ALL pushes (round-9):** while an adoption
intent is unresolved (any phase short of complete), the engine pushes
NOTHING — graph or hot — and the crash-recovery rollback (§1 D2 step 1)
runs before the engine's first cycle work. Otherwise a crash-recovered
device could publish half-adopted state, or mint circle IDs for imported
profiles that the rollback is about to delete.

**Retention & dormancy (round-3 revision):** manifests idle for more than
30 days are excluded from the hot union. Tombstones expire at 90 days, and
`staleManifestCutoff (30d) < tombstoneHorizon (90d)` keeps a dormant
device's SERVER doc from resurrecting deletions. **Bootstrap discovery is
explicitly EXEMPT from the 30-day cutoff:** within the bounded peer set, M5
examines every authentic manifest regardless of heartbeat age and selects the
newest complete, hash-verified bootstrap by the bootstrap SECTION's
`updatedAt` (deviceId tie-break). A dormant bootstrap is a recovery base, not
a member of the hot union; connection immediately follows it with the latest
eligible graph and the ordinary hot/tombstone merge. Thus a healthy folder
with only a 30+ day dormant bootstrap publisher remains connectable, while its
stale hot records still cannot overrule active peers. **Tombstones are
REPLICATED (round-5):** at each push, every device unions all live
tombstones it has seen into its OWN tombstones section — they're tiny,
additive, and the union converges so digests settle. Without this, a
deleter going offline takes its tombstones out of the union with its
manifest at day 30 (60 days early), and a brand-new joiner would never see
them at all; the per-device sections would silently defeat the horizon.
**Round-6 — replication spreads tombstones but does not guarantee DELIVERY;
three rules close the remaining holes:** (a) a tombstone is **pending until
published** — it never expires locally before this device has included it
in at least one successful push, so a deletion made during a 90+ day
offline stretch still propagates on reconnect instead of dying unheard —
**and its 90-day horizon counts from that FIRST PUBLICATION, not from the
deletion (round-7):** a removal made 60 days into an offline stretch would
otherwise reach the server with two-thirds of its horizon already burned,
resurrectable by any 30–89-day-dormant device that missed its short
remainder;
(b) tombstone sections are **EXEMPT from the 30-day stale-manifest
cutoff** — they stay in the union for the full horizon regardless of their
manifest's age (the cutoff exists to mute stale STATE; a stale device's
tombstones are precisely what must not be muted, else a sole publisher
going quiet at day 30 strands them before any peer pulls); (c) **Forget
device first materializes** the forgotten device's unexpired tombstones
into the actor's own section AND, before deleting a sole bootstrap publisher,
publishes and verifies an authentic current bootstrap+graph in the actor's own
manifest. If either continuity step fails, Forget device refuses. It then
deletes the directory. Its LOCAL copy is handled by the **dormant-rejoin
rule**: a device whose `lastSuccessfulSync` is
older than the tombstone horizon adopts the merged peer state as base and
overlays only local records stamped AFTER `lastSuccessfulSync` (its genuine
offline activity). Records from before dormancy were already published
pre-sleep — the peers' current state IS their verdict (kept or deleted), so
the local copies are discarded rather than re-unioned. No acknowledgement
protocol needed.

Failure posture: LAN-only server unreachable → silent skip, status only in
settings ("Last synced ✓ / retrying"). Never a launch banner, never a
snackbar for routine cycles. Diagnostics to the privacy log.

---

## 6. UX flows

**Settings → Sync and Migrate — its OWN top-level settings section (user
decision 2026-09-01), phone + TV DPAD page.** Sync never nests inside the
existing Backup & Restore page, and that page is not modified. The section
has two halves: **Sync** (shown as “WebDAV Sync” where qualification is
needed) and **Migrate** (one-shot WebDAV backup/restore, M2). The words
“circle”, “seed”, “join”, and “enrollment” do not appear in product copy.

**Sync half — login-first setup (§15):**

- The sole primary action is **Enable WebDAV Sync** (or **Change WebDAV sync
  account** after setup). It requires an Admin session and opens a dedicated
  login that never registers in Cloud accounts. Koofr pins
  `https://app.koofr.net/dav/Koofr/`, hides the URL, identifies the username as
  the Koofr email, and explains Koofr app passwords. Custom exposes the URL and
  an explicit warning for `http://`. Both use the fixed `Debrify` folder.
- The read-only setup probe GETs `Debrify/debrify-sync/circle.authority` first.
  Authentication failures remain inline and generic; server bodies,
  credentials, and secret material never enter errors or diagnostics. A valid
  authority means an existing root; 404 permits legacy-name probes and then a
  new root if those are also absent. A malformed authority always fails closed.
- There is no passphrase field, folder picker, start/join choice, sync name, or
  invitation code. The machine secret is sealed locally after setup/claim.
  WebDAV app passwords may legitimately differ by device or be rotated without
  changing the encrypted sync identity.
- **Hidden initialization safety:** M5 uploads and verifies the initial
  sections and non-empty seed manifest first, then writes the one authority
  LAST and always reads it back. Exact bytes finish; different valid bytes
  enter adoption. Conditional PUT is opportunistic, all 2xx responses are
  provisional, and Koofr's unconditional overwrite behavior is supported.
  Every active device pins the accepted authority bytes and verifies them on
  each cycle's first GET. A later deletion or replacement becomes a loud
  sync-root error and an internally consistent re-adoption, never an
  unopenable marker/secret split.
- **Existing local data:** finding an existing marker changes nothing by
  itself. **First connection to an existing root always shows** one explicit
  prompt: *“Use sync data from this account? Existing profiles and
  connections on this device will be replaced.”* Every initialized device has
  a managing Admin and first connection snapshots/prunes every local profile,
  so v1 has no genuine empty-prune silent path. Before any destructive step,
  automatically write and decrypt-probe one recoverable local `deviceGraph`
  safety backup under app support, encrypted with the sealed circle-key secret.
  It may
  use only the named database fallback above when the full graph exceeds the
  envelope budget. On tvOS that location is purgeable Caches, so the UI must
  not present it as a permanent backup; durable user backups remain the
  separate M2 WebDAV action.
  Then run the guarded internal CircleAdoption flow: bootstrap → latest graph
  revision → hot merge. Per-orphan one-tap exports remain impossible because
  `exportProfile` requires the acting profile to be the exported profile and
  child profiles cannot hold `backupRestore`; restoring an individual old
  profile is manual in v1, while union carry-in remains v2.
- **Status follows the persisted lifecycle, not optimistic connectivity.** M3
  may show Configured, WebDAV account verified, Ready to initialize, or Error,
  plus an action to re-enter the WebDAV password. It never shows
  Last synced. M4 supplies cycle/clock/peer telemetry behind the activation
  gate. Once M5 reaches Active, the UI exposes Last sync, Sync now,
  retry/clock state, Admin/prune blockers, graph-change prompts, the device
  list, and Forget device. Graph prompts remain a quiet badge + next-open
  dialog, never mid-playback; declined revisions do not re-prompt (§5).
- **Forget device** remains advanced bookkeeping, not setup and not
  revocation. It requires an Admin session, first materializes the forgotten
  device's unexpired tombstones, and ensures the actor's own verified
  bootstrap+graph will keep future connections possible before deleting that
  server directory (§5). Failure refuses the deletion. The dialog explains
  that an installed device still has the WebDAV password; real v1 revocation
  means changing that password on the server, while sync re-keying is v2.
- The carve-out copy (updated for §14): *“IPTV sources, favorites, history,
  resume state and Debrify TV channels stay in sync. Each device rebuilds
  its channel and guide caches.”* iOS and tvOS use the same flow;
  tvOS uses `TvTextField` with the system keyboard idiom and
  Keychain-backed `DeviceKeyProvider`, needs no folder/document picker, and
  still observes the low-memory/playback gates.

**Deliberate limits of automatic detection:** it checks only the fixed
`Debrify` folder under the effective endpoint; it does not scan parents,
siblings, or the whole WebDAV account. Possession of the WebDAV credentials is
sufficient in v1 because the server-side authority includes the secret with
the sealed marker;
there is no separate device-approval ceremony. Changing only the WebDAV
password does not rotate the sync encryption key. Creating a new sync
set requires a linearizable object store: the disposable sentinel PUT must be
returned exactly by its immediate GET. Conditional-create status and overwrite
behavior are irrelevant because the standing authority read-back decides.

M3 delivers the fresh-setup read-only login probe, local pending-binding state,
unchanged inner root wire format, strict authority/keyfile parsers, and exact
authority verification/pinning. It does not validate peer data or write a new
root or manifest; an authenticated legacy open may provision the merged
authority as specified in §15. M4
delivers the inactive hot-state engine against fixture/injected maps. M5
validates bootstrap-bearing manifests, completes the same single user flow,
proves linearizability, commits or adopts the single authority,
establishes real mappings, and is the first
milestone allowed to expose Active sync or profile replacement.

**Migrate half (M2):** "Save backup to WebDAV" + restore-from-WebDAV
browser — living HERE in **Sync and Migrate**, NOT on the Backup & Restore
page (user decision 2026-09-01; the existing Backup & Restore page stays
untouched). Fixes TV backup (no `ACTION_CREATE_DOCUMENT` there) and
exercises the full write path before sync ships. This means the Sync and
Migrate section EXISTS from M2, with only the Migrate half populated; the
Sync UI foundation lands behind the flag in M3 and becomes user-visible only
when M5 can complete and activate the flow.

---

## 7. Version skew & compat rules (carrying the tvOS boot-loop lesson)

- Every section carries `schemaVersion`; `circle.json` carries the schema
  floor ONLY — the graph ratchet is DERIVED from manifest claims, never
  stored centrally (§5; round-6 removed the contradiction where this line
  still said `circle.json` carries it).
- Reader supports `[floor..current]`; a **newer** section is skipped and
  preserved — never deleted, never overwritten, never blocks other sections.
- Graph revisions BELOW the ratchet are never applied (§5); hot-doc scalar
  merges use key-union + per-key provenance (§4.1/§13), so an older writer's
  win cannot drop newer-schema keys or lend freshness to an unrelated stale
  key. The §13 reader accepts legacy whole-stamped hot documents and expands
  their entries with the legacy parent stamp; writers publish the new schema.
  A still-running legacy writer can reintroduce whole-map arbitration, so all
  devices in a test circle must be upgraded before §13 is declared verified.
- Old devices keep pushing their own sections under their own directory —
  per-device dirs mean skew can never clobber newer data on the server.
- Graph payloads inherit `PortableProfilePackage` versioning
  (`oldestSupportedVersion` 3) — already tolerant.

---

## 8. Milestones (independently testable and flag-gated)

A partial engine slice is not exposed as “working sync” before it moves user
data safely. M3's setup foundation and M4's hot engine stay behind the gate;
M5 is the first milestone that can establish mappings, commit/adopt a root,
and transition a binding to Active. **This deliberately gives up incremental
user-visible delivery:** M3/M4 are engineering checkpoints, and
resume-everywhere is not demoable as a shipped feature until M5. The identity
map dependency makes that safer than exposing a temporary incompatible format.

| # | Deliverable | New code | Days |
| --- | --- | --- | --- |
| M1 | WebDAV protocol client: `putBytes`/`uploadFile` (streamed from disk) with MKCOL-on-409 for parents, `getBytes` (capped)/`downloadToFile` (streamed), `exists`; typed error contract; **transport hardening (round-6):** the sync client sets `followRedirects = false` and refuses cross-origin / scheme-downgrade redirects (the current client follows redirects with `dart:io` defaults, which replay the Basic credentials at the new location; `_baseUri` upgrades only scheme-LESS URLs — an explicit `http://` goes out as-is, `lib/services/webdav_service.dart:186`); explicit `http://` stays allowed but is labeled insecure in the WebDAV server config UI from M1 onward (round-11; LAN Nextcloud/rclone reality — hard-requiring HTTPS was rejected); full acceptance criteria below (rounds 10–11) | ~400 LoC protocol client + tests | 1–1.5 |
| M2 | Backup to/restore from WebDAV (phone + TV UI) — lands in the NEW **Settings → Sync and Migrate** section ("Migrate" half), NOT on the Backup & Restore page (§6); acceptance criteria below (round-10) | transport-neutral backup entry points + picker mode + new settings section | 1.5–2 |
| M3 | Login-first binding foundation: dedicated Koofr/Custom credentials that never enter Cloud accounts; fixed `Debrify` folder; persisted lifecycle states; fresh-setup read-only strict authority probe with authenticated legacy marker/key fallback; an authenticated legacy open may provision the merged authority as specified in §15; existing-root embedded-secret/key-check verification + exact authority pin (**peer/bootstrap validation waits for M5**); engine-owned transport credentials + machine secret sealed via `DeviceKeyProvider` (Linux locked-vault deferral); per-root device UUID/state namespace + isolated Change-account staging; frozen bounded root/manifest/authority codecs and golden/tamper/version tests. **M3 publishes no new-circle authority, manifest, hot data, or graph.** | binding service + login/setup component + codec tests | 1.5–2 |
| M4 | **Inactive hot-state engine** requiring an injected root context + authenticated profile AND resource circle↔local maps—absence is no-op and local IDs are never used on wire: peer discovery + peer-count/doc-size bounds; server-`Date` clockOffset capture, monotonic high-water mark, offset-delta damping, and normalized-time arbitration; hot-document semantic digests; deletion-path audit (**normative** — ships a test matching audited APIs to helper call sites) → tombstone helpers + replication + pending-until-published; two-part hot doc with `origin` stamps; merge module (pure functions, heavy unit tests: LWW + key-union + deterministic tie-break, alias-keyed playback unions + order stamps, completion diff-stamping, tombstones + cutoff exemption, dormant-rejoin, last-pushed dirty compare + convergence-stops-traffic, publish-time clamp, CW re-cap, **null-dropping doc build + never-delete-on-null apply, tombstone horizon from first publication — round-7**; **playlist per-item union by `computePlaylistDedupeKey` + diff-stamps + tombstones + order value, lossy-twin projection-equality rule — round-8**); `_exportPreferences` exposed additively; **scope-captured BATCH apply op (one tvOS checkpoint + one native projection — round-7) guarded by a persisted pending-apply target (round-8)**; trigger plumbing remains unarmed until M5, whose bounded seed/adoption transaction may invoke builders explicitly | merge module + helpers + gated glue | 5.5–6 |
| M5 | **Activation + graph tier.** New root: ensure + PROPFIND-verify the collection, prove linearizable exact read-after-write with one disposable sentinel, check whether a standing authority is the persisted candidate, then mint the single marker+secret authority; build/seal/upload/hash-verify initial sections; write/read-verify a non-empty seed manifest; PUT authority LAST and always read it back. Exact bytes win; a different valid authority atomically reseals its secret, invalidates stale candidate identity/state, and enters existing-root adoption. Conditional-create behavior never decides the result. Existing root: discover the newest complete bootstrap across authentic manifests **regardless of 30-day dormancy**, require first-connection replacement consent, then bootstrap→latest eligible graph→hot merge. Shared graph/adoption safety remains unchanged. Only after seed/adoption and real maps succeed does M5 transition Active and arm M4. | activation + graph/adoption flows + glue | 6–6.5 |
| M6 | Device-matrix hardening: simulated phone ↔ Mi Box ↔ tvOS ↔ desktop convergence; bounded/LRU hot-section cache; disk-staged large WebDAV transfer and integrity verification; tvOS memory/path audit; explicit scenarios for strict authority parsing, legacy upgrade, LWW concurrent initializers, authority deletion/replacement, 30+ day bootstrap discovery, bootstrap-less-authority rejection, mandatory first-connection consent, account rebind isolation, and M4 remaining inactive without maps. Physical-device soak remains a manual gate. | fixes + matrix tests | 1–1.5 |

Post-M6 correctness work is tracked separately in §13. Although M4's original
whole-scalar implementation passed its fixture matrix, the physical Koofr
failure invalidates that scalar acceptance assumption; WebDAV sync is not
ship-ready until §13's per-setting convergence gates pass.

### M3–M6 boundary acceptance gates

- Fresh M3 setup reads `circle.authority` first and only probes the legacy
  marker/keyfile names after a definitive 404. Ordinary missing/merged-layout
  inspection writes only local pending state; an authenticated legacy open in
  setup or repair may provision and read back the bounded merged authority
  described in §15. UI
  tests cover Koofr/Custom login, fixed folder, HTTP warning, generic inline
  authentication failures, and no Cloud-registry write or passphrase dialog.
- M3 persists lifecycle state and the exact accepted authority bytes (or the
  legacy marker pin until upgrade). After a restart, a pinned 404, changed
  bytes, malformed authority, or marker/secret authentication failure is an error and
  cannot enter `awaitingSeedCommit`.
- Root/manifest envelope golden vectors prove deterministic parsing, bounded
  KDF parameters, authenticated outer header, random nonce use, wrong-key and
  tamper rejection, and explicit newer-version rejection without rewrite.
- Change-account tests prove every root-scoped field is isolated and that a
  failed/cancelled staged binding resumes the previous active binding without
  touching either server folder. After a completed switch, returning to the
  old namespace cannot reuse its former Active state without marker + mapping
  target revalidation.
- M4 with missing root context, profile map, or resource map performs zero
  network, local apply, timestamping, tombstone expiry, and manifest writes.
  Fixtures prove no serialized path or payload ever contains a local profile
  or resource ID.
- M5 new-root tests assert wire order: collection verification → linearizable
  sentinel write/read/cleanup → standing-authority/candidate resume check →
  candidate generation → all bounded/hash-verified sections → non-empty
  read-back-verified seed manifest → final authority-404 preflight → one
  authority PUT → mandatory exact/valid-winner read-back. A malformed or absent
  read-back never activates; failure/crash before the last step leaves no
  accepted root. Adoption discards state sealed for a losing authority and
  cleans only that device's orphan. A never-returning creator's directory
  remains ignored accepted litter; peers issue no cross-device cleanup request.
- Concurrent-initializer tests use an unconditional-overwrite, linearizable
  LWW fake. Both read-backs converge on its one standing authority; the loser
  adopts the matching marker+secret together. Koofr-style ignored
  `If-None-Match` succeeds. Separate tests cover own-write 2xx followed by a
  different valid winner, non-persisting smoke-check failure, transient retry,
  strict authority parse failures, join, and authenticated legacy upgrade.
- M5 refuses Active when a marker has no authentic recoverable
  bootstrap-bearing manifest, when adoption's required backup fails its
  decrypt probe, carries an unknown/malformed omission, or whenever any
  adoption phase/map remains unresolved. An oversized fixture proves the two
  named database omissions retain IPTV credentials and durable state.
- A connection test with every bootstrap-bearing manifest idle for more than
  30 days still selects the newest complete bootstrap, then applies only the
  graph/hot/tombstone records eligible under their own freshness rules.
- First connection to every existing root prompts and verifies the safety
  backup before adoption; only new-root seeding has no replacement prompt.
  Forget-device refuses unless tombstone and bootstrap continuity are both
  verified first.
- M6's automated device matrix runs the same encrypted merge across phone,
  Mi Box, tvOS, and desktop fixtures, then proves convergence stops writes.
  Playback and tvOS low-memory gates suppress automatic and interactive heavy
  work; bounded section-cache tests cover eviction and authenticated metadata
  revalidation.
- Large graph/bootstrap network bodies upload and download through private
  scratch files with bounded size/hash verification and `finally` cleanup.
  **Honest memory limit:** v1 AEAD/JSON and the file-backed engine journal still
  decode one bounded document in memory (graph documents cap at 256 MiB;
  engine state caps at 64 MiB). This is bounded, not fully streaming crypto.
- Physical tvOS stores the engine journal and automatic safety backup in
  purgeable Caches because its sandbox does not provide writable durable app
  support. A missing journal never invents maps or resumes sync: it marks the
  binding as needing attention and requires marker/keyfile re-verification
  plus the normal consented adoption flow. A purged automatic safety backup is
  an accepted platform limitation and is not a substitute for an M2 backup.
- Koofr M1/M2 has a recorded real-provider smoke pass. Nextcloud 34.0.3,
  physical-tvOS, and physical multi-device soak remain deferred manual checks
  in `docs/architecture/webdav-m1-m2-manual-gate.md`.

### M1/M2 acceptance criteria (rounds 10–12 — implementation-spec reviews;
unchanged by the later M3–M5 product-flow and boundary corrections)

**M1 — the protocol client is a real client, not three functions:**
- Verbs take `(endpoint, credentials)` DIRECTLY — no `_authorize` inside
  the protocol layer (today every existing verb routes through it,
  `lib/services/webdav_service.dart:174`). Profile-facing callers (M2's
  backup UI) wrap authorization AROUND the verbs; the M3 engine calls
  them bare with its own sealed credentials.
- Transfers STREAM in BOTH directions (round-11 — downloads alone was
  half the fix): `downloadToFile` streams to a temp file under a byte
  budget (mirroring `readBoundedUtf8`'s budget-before-append pattern,
  `lib/services/profiles/portable_profile_package.dart:260`) and
  `uploadFile` streams a PUT from disk (`StreamedRequest`) — envelopes
  reach 128MB and a whole-body read OR write collides with the tvOS
  low-memory gate. `putBytes`/`getBytes` remain only for small files
  (manifests, hot docs) with explicit caps.
- Conditional requests + response metadata are first-class: PUT accepts
  `If-None-Match: *` / `If-Match`, 412 maps to a typed precondition
  result, and every response surfaces `Date` and `ETag` — M5's root-last
  create-only commit and M4's clock-offset capture depend on them.
- Redirects: collection URLs are normalized with trailing slashes (avoids
  the routine Apache/Nextcloud 301), then at most ONE same-origin,
  same-scheme redirect hop is followed; anything else — cross-origin,
  scheme downgrade, a second hop — fails loudly. **Method semantics
  (rounds 11–12): only GET and HEAD may follow any 3xx for their one hop.
  Every OTHER verb — PUT, MKCOL, DELETE, MOVE, and PROPFIND too (it
  carries a method-specific XML body; 303 converts it to GET and 301/302
  handling is ambiguous for non-GET verbs) — replays only on 307/308,
  the codes that preserve method+body; any other 3xx on those verbs
  fails loudly.** Every authenticated verb goes through this single hardened
  request path.
- MKCOL semantics per RFC 4918: **405 = collection already exists (treat
  as success), 409 = missing ancestor** (create parents outward, bounded
  retries — never unbounded). `exists` falls back to PROPFIND depth-0
  where HEAD is broken (405/501).
- **Typed error contract (round-11 — "error mapping" made concrete):**
  distinct results for authentication (401/403), not-found (404),
  conflict (409), precondition failed (412), quota (507),
  transient/rate-limit (429, 5xx), timeout/network/TLS, and malformed
  response (bad XML). **`exists` returns false ONLY on 404** — mapping
  401/403 to false would read as "not there" and trigger
  create/overwrite logic against a misconfigured server.
- The insecure-`http://` label ships HERE and in the M3 Custom sync login: M1+M2
  are independently shippable and can already send Basic credentials to
  an explicit `http://` endpoint. **Its M1 surface is the existing WebDAV
  server configuration UI (round-11); M2 repeats it in the Migrate
  destination picker; M3 repeats it without reusing that registry flow.**
- Testing: automated tests run against a local fake WebDAV server (CI);
  the real-Nextcloud check is a **documented, version-pinned MANUAL gate**
  run before shipping M1/M2 (round-11 decision — a Dockerized-Nextcloud
  CI job isn't worth the maintenance for two milestones).

**M2 — honest scope (it is not "glue"):**
- The existing backup flow hard-rejects tvOS and inlines the local file
  picker (`lib/screens/settings/profile_backup_flows.dart:69`); M2
  refactors it into transport-neutral create/restore entry points with
  local-file and WebDAV destinations. tvOS gets the WebDAV destination —
  that IS the TV backup fix. **Memory honesty (round-11): the envelope
  is packaged to a PRIVATE temp file, the in-memory bytes freed, and the
  upload streams from disk via `uploadFile`; under the tvOS low-memory
  gate the backup action defers.** (A fully streaming envelope codec was
  considered and TRIMMED — the shipped phone backup already materializes
  the envelope once, real packages are a few MB against the 128MB
  ceiling, and tvOS today has NO backup at all.) **M2 acceptance test
  (round-12): because M2 ships alone, a device test proves that a
  representative package AND a near-limit synthetic package either
  complete safely on tvOS or are refused/compacted BEFORE memory
  pressure; M6 records the remaining bounded-buffer limitations explicitly.**
- **Authorization lifecycle (round-11):** `backupRestore` permission AND
  the selected WebDAV connection resource's grant are captured (via the
  profile facade — M2 is profile-facing, exactly where that gating
  belongs) BEFORE export/download, and revalidated immediately before
  the upload or restore-commit; a mid-flow profile switch or revocation
  aborts. House pattern, stated.
- The existing WebDAV screen is a media browser — taps PLAY files
  (`lib/screens/webdav/webdav_files_screen.dart:977`). M2 adds a
  dedicated DPAD-safe folder/backup picker mode; it does not pretend to
  reuse the browser as-is.
- Remote backup names are **timestamp + random suffix** (round-12 — a
  timestamp alone is not collision-proof across two devices, and the
  current shipped stamp is even date-only:
  `debrify-profiles-YYYY-MM-DD.json`,
  `lib/screens/settings/profile_backup_flows.dart:234`, a silent
  same-day overwrite). Uploads use create-only PUT; **on 412, regenerate
  the suffix and retry — BOUNDED.** Verify-after-upload = streamed,
  bounded GET read-back with SHA-256 compared against the local digest
  (round-11 — the earlier "size/hash via PROPFIND" was not portable:
  standard PROPFIND offers `getcontentlength` and an OPAQUE `getetag`,
  no cryptographic hash). **Mismatch cleanup deletes ONLY when creation
  ownership is certain — the PUT returned 201 Created. A 204 (something
  was overwritten; the server ignored the precondition) or any ambiguity
  reports the mismatch and leaves the object untouched (round-12:
  auto-DELETE could otherwise destroy a pre-existing valid backup that
  the failed upload never actually replaced).** A temp-upload/MOVE commit
  was considered and TRIMMED — sync's content-addressed/manifest-last and
  M5 root-last commit protocols provide that durability where it is needed;
  manual backups do not grow the same machinery.
- **Temp hygiene + regression (round-11):** all staging uses private
  temporary storage with `finally` cleanup on EVERY exit — success,
  cancellation, wrong passphrase, oversize, network failure; and
  regression tests prove the local-file backup/restore path is unchanged
  by the transport-neutral refactor.
- The "Sync and Migrate" section costs what a settings section costs in
  THIS codebase: adaptive + TV index-based layouts, the settings-search
  registry, DPAD focus wiring, and their tests (the nav-index-audit
  lesson).

**Total v1: ~17–20 focused days** (round-6 re-estimate 16–18 up from 13–15:
the crash-ordered adoption flow, local-state carry-forward, prune
containment, tombstone delivery guarantees, and determinism hardening are
real scope, not polish; rounds 7–8 were line-level deltas absorbed within
it; round-10's honest M1/M2 criteria add the final day). The 2026-09-01
simplification reduces M3's UI/state-machine scope but moves clock, semantic
merge, graph-ID work, and the actual root commit to M4/M5 rather than deleting
safety work. M1+M2 is the first shippable slice (~3 days); M3 is the hidden
binding/codec foundation; M4 is an inactive but fully tested hot-data engine;
M5 activates the single login-first flow; M6 completes automated matrix and
resource hardening while retaining the named physical-device manual gates.

### Explicitly deferred to v2 (do not scope-creep into v1)
- Silent graph steady-state: per-category **set-reconcile** diff apply through
  the remote fast-path handlers (adds deletions-propagate; removes the prompt
  and the concurrent-Admin lost-edit trade).
- **Ongoing `debrify_tv.db` sync** (channels, IPTV favorites/lists, TV
  history): needs record-level treatment, not snapshot replace. v1 carries
  it on first full connection and preserves it across refreshes via
  copy-forward.
- **Sync re-key** (rotate the machine key → true device revocation).
- **Union carry-in on first connection**: automate carrying a connecting
  device's unique profiles into the shared graph as additional profiles.
  NOTE: **identity merge**
  (deciding two same-named profiles are the same person and combining their
  settings/histories) stays permanently out of scope.
- Key retention beyond one cycle (once-per-cycle derivation via the
  circle-fixed salt is M3 scope, not deferred).
- Version vectors / authenticated logical clocks (only if bounded
  server-time trust proves insufficient in practice).

---

## 9. Risk register / standing invariants

1. **`restoreDeviceGraph` is ADDITIVE.** Adoption/refresh must run the full
   CircleAdoption flow IN ORDER (**intent + pre-restore profile-ID snapshot
   + probe-verified backup FIRST** → restore → phase record + ID maps →
   drained DB copy-forward (temp+rename) → remap → local-state
   carry-forward → handoff with target open-gate → prune LAST). The join
   prune set is the step-1 snapshot; a refresh's is the engine's mapping —
   never name matching (round-7 resolved the join/mapping contradiction).
   **The intent PRECEDES restore** (round-7): restore's own journal is
   cleaned before it returns, so a crash before the engine record would
   otherwise leave unmapped imports that a retried join duplicates —
   recovery is current-profiles-minus-snapshot rollback, then a clean
   re-join. **Guards are MODE-SCOPED (round-8): a REFRESH prune never runs
   for a pair whose copy-forward, remap AND carry-forward have not all
   succeeded; a FIRST-JOIN prune (the snapshot set) is instead gated on
   verified backup + bootstrap restore + handoff — pre-circle profiles get
   no copy/carry, which would be the banned identity merge**; DBs copy
   only drained
   (`debrify_tv.db` + `iptv_catalog.db`, never via the generic file walk);
   prune revokes ALL other-profile grants (not just defaultSeed) and
   passes both dispositions (`deleteOwnedResources` +
   `detachPublicArtifacts`); quarantines on refusal; and **graph pushes
   are BLOCKED while any profile is prune-pending** — export includes
   disabled profiles, so withheld circle IDs alone contain nothing
   (round-6).
2. **Never publish an unreviewed partial graph**: full database snapshots are
   preferred; the bounded size fallback may remove only rebuildable IPTV
   catalogue/EPG rows and Debrify TV channels/hash pools. The two omission
   records are structurally validated; every unknown omission or post-compact
   oversize refuses the push and keeps the prior section. IPTV credentials
   remain encrypted graph resources and durable IPTV tables remain attached.
   **Hot docs share the posture (round-9): a doc exceeding the M4 size
   caps refuses the push and keeps the prior section + status warning —
   never a truncated doc.** And nothing pushes at all while an adoption
   intent is unresolved.
3. **Refresh graphs are STRUCTURE-ONLY (round-8): no DB snapshots AND no
   preference sections** — `exportAllProfiles` embeds every portable pref,
   so ordinary watching, playlist edits, or settings tweaks would
   otherwise restamp the graph digest and mint prompted revisions
   perpetually; the hot tier owns portable prefs. Continuity across
   refreshes is carry-forward (DBs + ALL pref keys with resource-ref
   remap), never the restore path. Bootstrap keeps everything and is
   regenerated when the profile set changes (+ daily-if-changed).
4. **Login-first connection, internal adoption model:** never ask the user to
   choose start versus join, browse a folder, enter a sync passphrase, or merge
   two pre-existing registries. Setup reads both marker and keyfile from the
   fixed `Debrify` folder and applies the four-state matrix in §15. M5 claims
   or adopts the keyfile before candidate use, uploads and verifies the full
   seed + non-empty manifest, then commits the marker LAST. An existing marker
   connects only after its keyfile secret and an authentic complete
   bootstrap-bearing manifest are verified. A BOUND 404 or marker-byte change
   is always a hard error, never reinitialization. Detection is non-destructive. Every
   first connection to an existing root requires explicit replacement consent
   and the verified pre-adoption recoverable-graph backup (with only the named
   database fallback allowed)—the snapshot contains at least the device's
   managing Admin, so v1 has no empty-prune shortcut.
5. **Per-device server dirs only** — no device ever writes another's files
   (Forget-device cleanup of a removed device's directory is the sole,
   guarded exception). A pre-root candidate's persisted device ID is reused
   and only that device may clean its losing/cancelled directory. If it never
   returns, the ignored directory is accepted server litter; peers never turn
   authentication failure into cross-device deletion.
6. **Root-last initialization; manifest-last ordinary commits;
   content-addressed and hash-verified throughout.** Never publish an empty
   manifest and never expose `circle.authority` before a complete seed manifest
   is uploaded and read-back verified. Before candidate use, a verified
   collection and exact sentinel write/read prove the required storage
   semantics. Root ownership requires a final 404 preflight, one authority
   PUT, and mandatory read-back: exact bytes win, while a different valid
   authority is adopted. A missing or malformed read-back never activates. A
   pre-root/racing peer directory participates only if it authenticates under
   the pinned root and declares the same circle ID. Never overwrite a section
   blob in place.
   Dirty detection compares
   SEMANTIC digests of canonical plaintext with circle-ID normalization,
   never sealed bytes and never local IDs — **against the device's own
   last-PUSHED digest only**. The adopted-digest echo-kill is REMOVED
   (round-6): every device republishes its merged union so state outlives
   its original author's manifest; convergence, not suppression, ends the
   traffic. Every device **pins its exact `circle.authority` bytes** and
   re-verifies them on each cycle's first GET — missing or changed bytes are a
   loud `RootChanged`; explicit reconnect authenticates the replacement and
   transitions into re-adoption, never a silent or unopenable split. M3 freezes
   the inner bounded root envelope: its canonical outer KDF header is authenticated as
   AAD and its encrypted body owns circle ID/schema/key-check; M4/M5 never
   mutate or reinterpret that root format.
7. **Skew never destroys**: unknown/newer sections preserved and skipped;
   graph revisions below the schema ratchet never applied; scalar merges
   key-union so older winners can't drop newer keys.
8. **Tombstones are write-side** and routed through central helpers covering
   EVERY deletion path (the audit is normative — the plan's list is not);
   read paths never filter (ghost-rows lesson).
   `staleManifestCutoff < tombstoneHorizon`, always; **tombstone sections
   are EXEMPT from the stale-manifest cutoff; a tombstone is pending until
   published at least once, never expires locally before that, and its
   horizon counts from FIRST PUBLICATION, not deletion (round-7); Forget
   device materializes the target's tombstones first** (round-6) — and the
   dormant-rejoin rule (§5) governs any device asleep past the horizon.
9. **Published docs carry server-normalized timestamps** (only
   locally-changed records re-normalize at build; adopted stamps are never
   re-adjusted); raw local state adjusts by the full measured offset at
   merge; **future stamps clamp at PUBLISH time** (merge-time clamping
   diverged per receiver — round-6); local unpublished state clamps at
   merge. Never publish a zero offset for a broken clock; **server `Date`
   is held to a monotonic high-water mark** (backward jump > 1h pauses
   publishing); **offset changes beyond 24h vs the last-accepted value are
   outliers — no stamping, no high-water advance — until they persist
   across consecutive cycles (round-7)**; LWW ties break deterministically
   by (time, origin deviceId, record hash). Tombstones replicate into
   every device's own section.
10. **Authorization captured at read**; mid-cycle profile switch aborts.
    **Hot-state apply is VERBATIM** — timestamp-preserving writes only,
    never through restamping mutation facades; cap-drops never tombstone.
    Apply is ONE batch operation (single tvOS checkpoint, single native
    projection), and **a null or absent doc entry NEVER deletes local
    state** — hot deletion is tombstones-only (round-7). A persisted
    pending-apply target guards the batch: on crash, re-apply VERBATIM
    before any diff-stamping or normalization runs (round-8). Record
    equality is judged on the portable projection — a lossy twin never
    beats its local original (round-8).
11. **No sync work during playback on TV / under tvOS low-memory gate.**
12. **Trackers outrank sync** for watch state: merged hot state is just more
    local state under the existing resume reconciler, which resolves
    trackers above it at read time. (Round-6 correction: the earlier "never
    write local completion when a tracker is connected" clause was
    factually wrong — `WatchedActionCoordinator` writes local
    UNCONDITIONALLY by design, "Local is unconditional; remote writes
    follow the Scrobble selection",
    `lib/services/watched_action_coordinator.dart:18`. Sync must neither
    add nor remove tracker gating the app doesn't have.)
13. **Profile credentials only ever travel inside the encrypted graph package** —
    hot docs are portability-filtered prefs, which already exclude them.
    Sync transport creds + the machine circle-key secret are engine-owned,
    device-level, sealed **via `DeviceKeyProvider` (platform keystore —
    round-7), never SecretVault**; a locked Linux vault defers the cycle.
14. **LAN-only servers degrade silently.**
15. Manual backup passphrases are separate from WebDAV Sync. Sync has no
    passphrase UI. The automatic pre-adoption safety backup encrypts with the
    sealed circle-key secret; consequently that local backup plus the server
    keyfile is sufficient to decrypt it.
16. **"Forget device" is bookkeeping, not revocation** — the UI must say so.
    Before deletion it materializes tombstones and guarantees at least one
    other authentic bootstrap-bearing manifest (publishing/verifying the
    actor's own if needed); otherwise it refuses.
17. **No authenticated profile AND resource circle↔local maps means no hot
    sync.** M4 never puts a local profile/resource ID on the wire and never
    arms production triggers by itself; missing maps are inactive/no-op. M5
    creates/restores both maps, completes seed/adoption, and alone transitions
    the binding to Active.
18. **Root state never crosses account bindings.** Marker pins, per-root device IDs,
    mappings, digests, tombstones, peer/clock state, ratchets, declined
    revisions, and pending operations are namespaced by authenticated circle
    ID. Change-account stages an isolated binding and switches only after safe
    M5 activation. A retained old binding must revalidate its marker and all
    mapped local targets before reactivation; password rotation within the
    same pinned root changes only credentials.
19. **Bootstrap discovery ignores heartbeat dormancy.** The 30-day cutoff
    excludes stale manifests only from the hot union; it never makes a valid
    encrypted folder unconnectable. M5 searches the bounded authentic manifest
    set regardless of age, chooses the newest complete/hash-verified bootstrap
    by section time + deviceId, then immediately applies graph/hot/tombstone
    data under each tier's normal freshness rules.
20. **Scalar provenance is per setting, never per map (§13).** A local change
    to one portable preference must not restamp another key, and a device
    rebuilding or republishing its scalar projection must preserve every
    unchanged key's time + origin verbatim. The outer scalar digest may decide
    whether bytes need publishing, but it has no conflict-resolution authority.
    Legacy whole-stamped documents are migration inputs only; all physical
    devices in a circle must run the repaired reader/writer before soak results
    count.

## 10. Remaining product decisions (small, non-blocking — defaults chosen)

- Naming is FIXED (user decision 2026-09-01): the settings entry is **Sync
  and Migrate**, the feature is **WebDAV Sync** where qualification is
  useful, and the primary action is **Enable WebDAV Sync**. “Circle”,
  “seed”, “join”, and “enrollment” are implementation vocabulary only and
  must not appear in UI copy.
- Prompted graph refresh cadence: badge quietly + ask on next open (default),
  vs modal immediately.
- Tombstone horizon 90 days / stale-manifest cutoff 30 days (defaults) —
  any pair works while cutoff < horizon.

---

## 11. v2 — Silent per-record sync for connections, addons, and profiles

Status: IMPLEMENTED 2026-09-03 (tasks A/B/C on `webdav-sync`) with the
design-round corrections summarized in the header. Preconditions 1-2 were
already fixed in-tree before the tasks ran; precondition 5 was subsumed by
the graph trim.

### 11.1 Product goal

The user's model is: **whatever is in the sync folder is the truth, resolved
per record by timestamp, and users never see a merge.** v1 already delivers
this for watch progress, continue watching, finished marks, playlists,
favorites, and series source bindings; §13 completes the same guarantee for
portable scalar settings. v2 extends the rule to the two record classes that
today live in the prompted graph tier:

1. **Connections and addons** — debrid keys, Stremio addons, IPTV/WebDAV
   endpoints, their grants and per-profile settings.
2. **Profiles** — create, rename, avatar, policy, PIN, lock settings, delete.

After v2 the prompted graph tier carries **only database snapshots** (full,
or bounded-compacted per §1 D1)
(`debrify_tv.db`, IPTV catalog) and profile bootstrap for first connection.
Structural edits stop minting prompted revisions. Ongoing database sync
remains v3 (see 11.8).

Explicit non-goals carried from §8: identity merge of same-named profiles,
sync re-key, union carry-in on first connection.

### 11.2 Why v1 prompts, and what v2 changes

v1 applies the graph by **adoption (replace)** because the registry has no
per-record timestamps and no deletion markers for resources. "Newest wins"
therefore only exists at whole-graph granularity, and replacing a whole graph
is destructive, so it asks. Two side effects follow:

- A pending remote revision blocks local structural publication until it is
  applied or declined (`webdav_sync_graph_tier.dart` checks remote change
  before `identitiesChanged`). Two devices adding different connections
  concurrently: the second to accept loses its own.
- Without tombstones, a connection deleted on one device is resurrected by
  a device that has not synced yet.

v2 fixes both by giving these records the same three properties the hot tier
already relies on: **per-record `updatedAt`**, **tombstones on delete**, and
**circle-stable identity via the existing identity maps**.

### 11.3 Current shape (verified 2026-09-02)

- `ConnectionResource` (`lib/models/profiles/connection_resource.dart:56`):
  id, type, label, ownerProfileId, publicConfig, publicSchemaVersion,
  authorizationRevision, enabled. **No timestamp.**
- Registry tables involved (`profile_registry.dart:237-282`):
  `connection_resources`, `profile_resource_grants`,
  `profile_resource_settings`, `profile_connection_bindings`, plus
  `resource_secret_chunks` (sealed per device via `DeviceKeyProvider`).
- Secrets are revealable only by the owning profile
  (`revealOwnedSecretForProfileBackup`); the graph tier sidesteps this by
  requiring an Admin session and exporting registry-wide.
- `UserProfile` (`lib/models/profiles/user_profile.dart:5`) **already has**
  `createdAt`, `updatedAt`, `disabledAt`, PIN state, policy, role, lifecycle.
- The hot document is per profile (`WebDavSyncHotDocument.circleProfileId`).
  Resources are registry-wide with an owner, so they need a **new
  circle-wide section**, not a field on the per-profile document.
- Identity maps (`localToCircleResources` / `circleToLocalResources`) already
  translate random per-device resource IDs for the hot tier. Reused as-is.
- Registry + connection service are ~6.3k lines; every write path in them is
  a stamp site.

### 11.4 Design

**Timestamps.** Add `updatedAtMs` to `connection_resources`,
`profile_resource_grants`, `profile_resource_settings`, and
`profile_connection_bindings`. Bumped by the registry writer, never by
callers. Stamps are device-local wall time, clamped for publication by the
existing server-clock policy (`clampForPublication`) exactly like playback
records.

**New hot section: `resources`.** Circle-wide, one per publishing device,
merged across all device manifests. Records:

- `resource` keyed by circle resource ID: type, label, ownerCircleProfileId,
  publicConfig, publicSchemaVersion, enabled, `updatedAt`, plus an
  encrypted `secretConfig` envelope (see Secrets).
- `grant` keyed by (circle profile, circle resource): permissions,
  `updatedAt`.
- `setting` keyed by (circle profile, circle resource): enabled, settings
  map, `updatedAt`.
- `binding` keyed by (circle profile, circle resource): `updatedAt`.

Merge rule: last-writer-wins per record on `updatedAt`, tie-broken by origin
device ID, identical to `_tombstoneBeatsRecord`. Tombstones for all four
record kinds, recorded at the registry delete chokepoints and covered by the
tombstone audit (which must become an all-sites assertion — v1 review
finding).

**New hot section: `profiles`.** Circle-wide. Record per circle profile:
name, avatarKey, role, policy, lockOnResume, inactivityTimeoutMinutes,
setupComplete, lifecycle, `updatedAt` (already present locally). PIN carried
as the sealed verifier + recovery-code hash set, not plaintext. Tombstone on
delete.

**Secrets on the hot path.** Two options; pick (a):

- (a) **Owner-scoped publication.** A device publishes `secretConfig` only
  for resources owned by the active profile at cycle time; other resources
  publish metadata only. Receiving devices adopt metadata immediately and
  mark the resource `secretPending` until a cycle from the owner's session
  supplies it. Keeps the existing "owner reveals" invariant; no new
  authority.
- (b) Admin-scoped reveal — adds a new reveal authority to the registry.
  Rejected for v2: wider blast radius on the credential-security invariants.

Secret envelopes reuse the M3 sealed-document codec under the sync key; the
server never sees plaintext.

**Apply side.** Merged records are applied through the **existing registry
writers** (`prepareConnectionResource` / `StagedGraphResource` paths used by
adoption), never by raw SQL, so grants, settings, bindings, and secret chunks
stay consistent and `authorizationRevision` bumps as today. Foreign IDs are
minted into the identity maps on first sight; the adoption remap helper
(`remapResourceReferences`) is reused for the preference keys that embed
resource IDs (playlist view modes, Stremio TV favorites, startup channel —
v1 review finding #8 must be fixed first so these are mapped at all).

**Profile lifecycle on remote change.**
- Remote create: registry insert, empty databases, no bootstrap needed.
- Remote rename/avatar/policy/lock: in-place update; if that profile is the
  active session, re-evaluate policy immediately.
- Remote PIN change: replace verifier; if the profile is currently unlocked
  on this device, **do not** force a lock mid-session — lock on next resume.
- Remote delete while signed in: finish the current cycle, then route to
  the gate on next foreground with the standard "profile no longer
  available" copy. Never mid-playback (existing TV gate).
- A locally created profile that has never been published is never pruned
  by a remote apply (tombstones, not absence, drive deletion).

**Graph tier after v2.** Refresh graphs are removed. The bootstrap section
remains for first connection and daily DB-content regeneration. The
"remote change → prompt" path only fires for bootstrap database replacement,
which no longer happens in steady state.

### 11.5 Effort

| Piece | Days | Notes |
|---|---|---|
| Timestamps on 4 registry tables + all write sites | 1.5 | widest edit; mechanical |
| `resources` hot section: models, codec, merge, tombstones | 2 | pure-Dart, exhaustively testable like hot_merge |
| Owner-scoped secret publish + `secretPending` apply | 1.5 | the one real design decision |
| Apply via registry writers + identity-map minting | 1 | reuses adoption helpers |
| **Connections + addons subtotal** | **6** | |
| `profiles` hot section + merge + tombstones | 1.5 | timestamps already exist |
| Remote lifecycle handling (PIN, delete-while-active, policy) | 1.5 | gate/lifecycle code |
| **Profiles subtotal** | **3** | |
| Tombstone audit → all-sites assertion | 1 | v1 review finding |
| Convergence matrix extended to new records | 1 | existing 4-device harness |
| Remove refresh graph path; bootstrap-only graph tier | 0.5 | deletion |
| **Cross-cutting subtotal** | **2.5** | |
| **Total** | **~11.5 working days** | 2–2.5 calendar weeks |

Order: connections first (it builds the section/tombstone machinery),
profiles second, graph-tier trim last.

### 11.6 Regression exposure

**Connections and addons — medium-high.**
- Every registry write site touched. Guarded by the profiles isolation suite
  and `profile_source_guard_test`; expect them to catch stamp omissions.
- Tombstone rule extends to a new record class; the v1 audit test cannot
  catch a missed site (text-slicing), hence the audit rewrite is in scope.
- Owner-only secret reveal is a credential-security invariant; option (a)
  preserves it, but `secretPending` is a new UI/runtime state that must not
  be confused with "connection broken".
- Hot merge itself is pure functions with strong tests; low risk there.

**Profiles — medium.**
- Fewer write sites and timestamps exist, but remote delete and PIN change
  touch the gate/lifecycle code where the app has historically had the
  subtlest bugs (see `project_settings_double_focus`, import blank-screen
  RCA, revision drift invariant).
- Same-profile `switchTo` not republishing scope (v1 review, plausible) must
  be resolved first or remote apply on the active profile races it.

**Shared.**
- Identity-map minting on first sight of a foreign record is new; a bug
  here duplicates resources circle-wide. Covered by the convergence matrix.
- No change to the wire envelope, clock policy, transport, or activation.

### 11.7 Preconditions (from the 2026-09-02 v1 review)

Must land before v2 starts:
1. Startup-gate hangs (`main.dart:237` unconditional re-hold;
   `webdav_sync_runtime.dart:469` StateError with no journal).
2. Tombstone recorder ordering (`webdav_sync_tombstones.dart:46` limits
   before no-binding short-circuit; `:29` scope check after return).
3. StringList portable preferences rejected by the scalar gate
   (`webdav_sync_hot_merge.dart:326`).
4. Composite-string preference remap (`webdav_sync_hot_merge.dart:193`) —
   v2 relies on `remapResourceReferences` for these keys.
5. Publish-before-check reorder in `maintain()` so local structural edits
   are never blocked by a pending remote revision (also removes the
   concurrent-Admin lost-edit trade in the interim).
6. §13 per-setting scalar provenance, including legacy-hot-document upgrade
   and the physical Koofr Mac ↔ Android convergence gate.

### 11.8 Still deferred after v2

- Ongoing `debrify_tv.db` / IPTV catalog sync: whole SQLite files with no
  row-level change tracking. Silent sync needs per-row stamps in those
  tables or accepts file-level LWW (loses data under concurrent use).
- Sync re-key / true device revocation.
- Union carry-in of a joiner's unique profiles; identity merge permanently
  out.

### 11.9 Acceptance gates

- Add a Real-Debrid key on device A; device B has it, with secret, within
  one cycle of B's owner-profile session, with no prompt.
- Delete a connection on A; it does not resurrect on B after B's next cycle
  from a stale state.
- Concurrent add of different connections on A and B: both exist on both
  after two cycles.
- Rename/PIN/policy change on A applies on B in place; an unlocked session
  on B is not interrupted, and locks on next resume.
- Delete a profile on A while B is signed into it: B finishes the cycle,
  reaches the gate on next foreground, never mid-playback.
- Refresh graph revisions are never minted; the "apply change" prompt fires
  only for bootstrap database replacement.
- Tombstone audit enumerates every `prefs.remove` / registry delete site
  for synced keys and fails on a new unguarded one.
- 4-device convergence matrix passes with `resources` and `profiles`
  sections included.

---

## 12. v2 — Near-real-time propagation and cycle speed

Status: IMPLEMENTED 2026-09-03 on `webdav-sync` (D12-1..D12-4). One
deliberate deviation: the local-change debounce is a coalescing window that
opens at the FIRST write of a burst (a resetting trailing debounce would
starve pushes under steady playback saves). The §12.10 physical Koofr trace
met D12-4's gate, so latency-critical hot/tombstone section read-backs were
removed in favor of PUT-response metadata validation; bootstrap, profiles,
resources, large-section, and manifest read-backs remain byte-for-byte. The
cycle front half now overlaps the root GET with device listing, and production
cycles/polls reuse one generation-fenced HTTP client per binding. Line
references below are to the pre-implementation tree.

### 12.1 Product goal

A change made on one device shows up on the others within about a minute,
without anyone pressing "Sync now", and a cycle is cheap enough to run that
often. v1 as built is correct but batch-shaped: it syncs on lifecycle edges
and on a 15-minute timer. §12 keeps every v1 invariant and adds two
triggers plus the measurement needed to make the cycle itself fast.

Target after §12, both devices in the foreground on the home screen:

- a local edit is pushed within ~10 s of the last write;
- a peer's push is visible locally within the poll period (60 s) plus one
  cycle;
- an idle cycle costs a handful of small requests and no section transfer.

### 12.2 Why v1 is slow to propagate (verified 2026-09-02)

- `WebDavSyncScheduler` (`webdav_sync_scheduler.dart:28-29`): triggers are
  `launch`, `foreground`, `playbackStopped`, `background`, `periodic`
  (15 min), `manual`; every non-manual trigger shares one 45 s debounce.
  All are wired (`main.dart:726`, `webdav_sync_runtime.dart:553-572`).
- **No trigger fires on a local write.** A favorite, playlist edit,
  settings change, or watch-progress save never reaches the scheduler; only
  playback stop and app background push. A TV or desktop parked on the home
  screen pushes nothing for up to 15 minutes.
- **Pull is polling by nature** (WebDAV cannot notify) and the only poll is
  the 15-minute periodic cycle, so a peer sees a change only when its own
  next cycle runs.
- Cycle cost, in execution order (`webdav_sync_engine.dart:169`): root
  marker GET + pin compare → `listDeviceIds` PROPFIND → one manifest GET per
  device, sequential (`_readManifests`, `:571-584`) → per mapped profile,
  peer section GETs (content-addressed; unchanged sections come from
  `_sectionCache`) → merge/apply → for every changed own section a PUT
  followed by a full GET read-back and byte compare (`_pushChanged`,
  `:880-897`) → manifest PUT + read-back (`:945`). Everything is
  sequential.
- Not a cost: the Argon2id root open is cached across cycles, keyed by
  binding revision + marker bytes (`webdav_sync_runtime.dart:720-732`), and
  runs off-thread.
- No per-cycle timing exists, so "slow" cannot yet be attributed to a
  step. D12-1 fixes that first.

### 12.3 Design

**D12-1 — Instrument before optimizing.** Each cycle records one redacted
`DiagnosticLog.instance.recordEvent` line: trigger, peer count, per-phase
wall time (root, list, manifests, sections, merge/apply, seal, push,
read-back, total), request count, bytes up/down, disposition. The Koofr
trace with at least one peer is pasted into §12.10 before D12-4's verify
change is decided.

**D12-2 — Local-change trigger.** New `WebDavSyncTrigger.localChange`.
Source: the single ordinary-write chokepoint `ProfilePreferences._write`
(`profile_preferences.dart:640`) — after a successful write with
`_capturedAccess == null`, `_scope != null`, and a `logicalKey`, notify a
static `WebDavSyncLocalChangeSink` with (scope, key). Captured-scope
writes (migration, restore, creation, `syncApply`) never notify, so the
engine's own applies cannot trigger a cycle. The tombstone recorder
(`WebDavSyncTombstoneRecorder.recordForProfile`,
`webdav_sync_tombstones.dart:51`) notifies the same sink for deletes. The
sink is synchronous, non-blocking, never throws, and adds no `await` to the
write path.

Key filter, reusing existing classification only: notify when
`ProfilePreferencePortability.allowsKey`
(`profile_preference_portability.dart:14`) admits the key OR the key is one
the hot builder reads raw — the constants at
`webdav_sync_hot_merge.dart:487-494` (`playbackPreference`,
`continueWatchingPreference`, `finishedMoviesPreference`,
`playlistPreference`, `playlistFavoritesPreference`, `seriesSourcePrefix`,
and the rest of that block). A test asserts every key the builder reads is
admitted by the filter, so the two cannot drift.

Coalescing lives in the scheduler, not the sink: a trailing debounce of
**10 s** (`localChangeDebounce`) collapses bursts; while playback is active
on any platform the debounce is **60 s** (`playbackDebounce`), so progress
saves become at most one push per minute. `localChange` is exempt from the
shared 45 s lifecycle debounce (as `manual` is) and subject to every
existing gate (`playbackActiveOnTelevision`, `tvOsLowMemory`, `_running`).
A notification that arrives while a cycle is running sets
`_dirtyDuringRun`; when the cycle finishes, the scheduler schedules one
follow-up `localChange` after the debounce, so an edit made mid-cycle is
not deferred to the 15-minute timer.

**D12-3 — Remote-change poll.** New `WebDavSyncTrigger.remoteChange` and a
poll timer with period **60 s** (`remotePollPeriod`), armed together with
the scheduler, paused on `AppLifecycleState.paused`/`detached` and resumed
on `resumed` (the runtime already receives these,
`webdav_sync_runtime.dart:553`). Each tick:

1. Skip when `peerCount == 0`, when any existing gate holds, or when a
   cycle is running.
2. For each peer device ID known from the last cycle, call a new
   `WebDavSyncTransport.probeManifest(deviceId)`, implemented with the M1
   `exists()` HEAD (PROPFIND depth-0 fallback,
   `webdav_protocol_client.dart:388`) on `devices/<id>/manifest.enc`.
   Validators, in preference order: `ETag`; else `Last-Modified` +
   `Content-Length` from the response headers.
3. Compare to the validator stored per peer in engine state after the last
   full read. Any difference, or a 404 for a previously seen peer, signals
   `remoteChange`, which runs the ordinary full cycle. Nothing else changes:
   the cycle still hash-verifies everything it reads; the validator only
   decides whether to look.
4. Probes are concurrent (bounded 4). A probe error never surfaces as a
   sync error: on 429/5xx/network failure the poll backs off exponentially,
   capped at the 15-minute period, and the status card shows "checking
   paused". A server that returns neither `ETag` nor `Last-Modified`
   disables the poll for that binding (status: "server does not report
   changes; syncing every 15 min").

New device directories are still discovered only by the full cycles
(lifecycle + 15 min); joining is rare and that latency is accepted.

**D12-4 — Cycle speed, measurement-gated.**

- Start the root-marker GET and device listing together, but authenticate and
  compare the root pin before consuming the listing. A root failure or mismatch
  discards the listing and performs no manifest reads. The commit-time root
  recheck remains sequential immediately before manifest publication.
- Read peer manifests and peer sections concurrently, bounded 4, results
  merged in a deterministic order. Same outputs as sequential; the
  convergence matrix proves it.
- **Section read-back (gate met; executed 2026-09-03):** after a successful hot
  or tombstone PUT, issue no full GET or HEAD. Validate response metadata when
  the server supplies it: a present `ETag` must be non-empty and explicit
  stored-resource size metadata must match the bytes sent; the response body's
  own `Content-Length` is not a stored-resource size. Missing metadata is
  accepted. Keep byte-for-byte read-back for bootstrap, profiles, resources,
  the large-section path, and the **manifest** commit record. Sections are
  immutable, content-addressed, and AEAD-sealed; every reader independently
  checks content hash, AEAD, and semantic digest. After any failed immutable
  section PUT, regardless of the provider's conflict status dialect, the
  content-addressed object is read back and accepted only when its hash and
  size match the local bytes and it authenticates; a mismatch rethrows the PUT
  failure. If this device later rejects one of its own referenced sections,
  clear its last-pushed digest so the next cycle republishes it.
- Production cycles and the remote-change poll borrow one long-lived HTTP
  client plus its generation for the active binding, preserving per-request
  credentials while reusing connections/TLS. Per-transport `close()` does not
  close that shared client. Scheduler disarm, reconfiguration pause, binding
  change/removal, and runtime reset bump the generation and close only the
  current client. Stale poll contexts abort before probing. A network-kind
  failure keeps the owned client for the next use; lifecycle teardown still
  closes it.

**Status surface.** `WebDavSyncRuntimeStatus` (`webdav_sync_runtime.dart:79`)
gains `lastPushMs`, `lastRemoteChangeMs`, and a `pollState` enum (active,
pausedBackoff, disabledNoValidators, gated). The existing status card shows
one extra line. No new page, no frequency setting.

### 12.4 Non-goals (do not build)

- No server-side notification: no WebSocket, long-poll, or push service.
- No new file in the server layout (no heartbeat/beacon object).
- No change beyond §13's already-landed scalar repair to the merge module,
  hot/graph wire format, clock policy, crypto, activation, adoption, or the
  graph tier's 6 h cadence (§11 owns the graph tier).
- No new key taxonomy: the D12-2 filter reuses `allowsKey` and the
  builder's own constants; the only key-specific behavior is the playback
  debounce.
- No OS background execution: the poll runs only while the app is in the
  foreground. The 15-minute periodic and lifecycle triggers are unchanged
  and remain the safety net.
- No user-facing "sync frequency" control. Emergency override follows the
  existing `DEBRIFY_WEBDAV_SYNC` dart-define pattern
  (`webdav_sync_feature.dart`) with `DEBRIFY_WEBDAV_SYNC_POLL` (default
  true).

### 12.5 Effort

| Piece | Days | Notes |
|---|---|---|
| D12-1 per-cycle instrumentation + Koofr trace | 0.5 | additive; one log line |
| D12-2 sink in `_write` + tombstone recorder, filter drift test, scheduler coalescing + dirty-rerun | 1 | scheduler is pure Dart, unit-testable |
| D12-3 `probeManifest`, poll timer, gates, backoff, validator state, status fields + card line | 1.5 | fake-server tests for ETag / no-ETag / 429 |
| D12-4 concurrent peer reads | 0.5 | bounded `Future.wait` |
| D12-4 selective section verify (trace gate met) | 0.5 | hot/tombstone metadata-only; high-value and large read-backs kept |
| Convergence matrix: "edit → peer sees it within poll period" | 1 | existing 4-device harness |
| **Total** | **~5 working days** | 4.5 without the verify change |

Order: D12-1 → D12-2 → D12-3 → D12-4. D12-2 alone already removes the
"nothing pushes until playback stops" gap and is worth shipping on its own.

### 12.6 Regression exposure

**`_write` (D12-2) — medium.** It is the hottest write path in the app and
the profiles isolation suite pins its behavior. The sink adds one
synchronous, exception-swallowing call after the existing native projection
and tvOS checkpoint; it must not add an `await`. Captured-scope exclusion is
load-bearing: if `syncApply` writes ever notified, every remote apply would
schedule a local push — a no-op by last-pushed digest compare, but a wasted
cycle. Test: apply N remote records → zero `localChange` signals.

**Poll (D12-3) — low-medium.** More requests per hour: at most `peerCount`
HEADs per minute while foreground, typically 1–3. Risks are provider rate
limits (backoff handles them) and servers with unstable `ETag`s (a spurious
change costs one idle full cycle, which is exactly what D12-1 makes cheap to
see). The poll never writes and never changes what the cycle trusts.

**Concurrency (D12-4) — low.** Reads only; result order is made
deterministic before merge. The bound of 4 keeps tvOS memory flat.

**Section verify (D12-4) — the one durability trade.** Hot and tombstone pushes
lose the pusher's immediate detection of a server that stores a corrupted body
while reporting success and no contradictory PUT metadata. Kept protections:
TLS integrity in transit, PUT metadata checks when available, AEAD +
content-hash and semantic-digest verification by every reader, dirty-on-own-
read failure, and unchanged high-value/large/manifest read-backs. The §12.10
measurement gate was met.

### 12.7 Preconditions

None from §11's new resource/profile design. §13 is mandatory first: faster
on-write pushes would otherwise make the whole-scalar overwrite bug happen
more quickly and more often. §11.7 items 1 and 2 (startup-gate hang;
tombstone recorder ordering) are independent bug fixes and should also land
first because D12-2 hooks the tombstone recorder and D12-3 runs on the startup
path.

### 12.8 Still deferred after §12

- Sub-10-second propagation (needs a notification channel; out of scope
  for a dumb-server design).
- Background (screen-off) sync on mobile.
- New-device discovery faster than the 15-minute cycle.
- Making the graph tier (§11) faster than its 6 h cadence.

### 12.9 Acceptance gates

- Add a favorite on device A (foreground, idle): A pushes within
  `localChangeDebounce` + one cycle, with no user action.
- Device B (foreground, home screen, idle) reflects A's change within
  `remotePollPeriod` + one cycle, with no user action. Convergence harness.
- Ten rapid edits on A produce one push.
- A write landing during a running cycle is pushed by an automatic
  follow-up cycle, not by the 15-minute timer.
- During phone playback, progress saves produce at most one push per
  `playbackDebounce`; on television, zero pushes during playback (existing
  gate, asserted).
- `syncApply` writes never signal `localChange`.
- Every key read by `WebDavSyncHotMerge.build` is admitted by the
  local-change filter (drift test).
- Fake server without `ETag`/`Last-Modified`: poll disabled, status says
  so, the 15-minute cycle still converges. Fake server returning 429: poll
  backs off to ≤ 15 min and no error is surfaced.
- App backgrounded: no probe is sent after the next tick; resumed: poll
  resumes and the existing foreground cycle runs.
- Every cycle emits one timing line; the Koofr trace is recorded in §12.10
  before the D12-4 verify change is started.
- Concurrent peer reads: convergence matrix output identical to
  sequential.
- Full suite and profiles isolation suite: no new failures versus the
  pre-§12 baseline.

### 12.10 Measurements

Physical-provider trace captured against a real Koofr circle on 2026-09-03
using the shipped per-cycle instrumentation. Observed cycles cost 2.3–14.2 s
wall. One 14,250 ms cycle reported: root 4,663 ms; list 200 ms; manifests
1,106 ms; sections 4,891 ms; merge/apply 112 ms; seal 1 ms; push 2,306 ms;
read-back 925 ms. Individual requests cost roughly 0.3–1.5 s on this provider.
Before the change, every cycle and poll constructed a fresh protocol client,
so each began with fresh connections/TLS. These measurements met the D12-4
gate and justify removing hot/tombstone section read-backs, overlapping the
root/list front half, and reusing one generation-fenced binding client;
high-value, large-section, and manifest commit read-backs are retained.

---

## 13. v1 correctness repair — per-setting scalar provenance

Status: IMPLEMENTED 2026-09-03 on `webdav-sync` (hot schema v2, per-key
stamped scalar entries, in-memory v1 translation, first post-upgrade publish
rewrites v2). The physical Koofr regression repeat remains the manual gate. This is a hot-model/merge repair,
not a provider-settings UI change and not part of §11's resource/profile work.

### 13.1 Confirmed failure

The physical Koofr Mac ↔ Android test produced two authentic hot documents for
the same Admin circle profile:

- macOS published `default_torrent_provider_v1 = torbox` at
  `1788368335000`;
- Android published its stale `default_torrent_provider_v1 = none` at
  `1788368350000`, 15 seconds later;
- every later merge selected `none`, because all values in an implemented
  `WebDavSyncScalarPart` borrow the part's single stamp.

The Mac write reached the sync engine and the phone page was freshly loaded;
this was neither a stale widget nor a failed WebDAV request. The encrypted
remote documents established the overwrite directly.

Root cause: `WebDavSyncHotMerge.build` hashes the complete portable scalar map.
If any scalar differs from the prior baseline, it gives the complete map a new
stamp. `merge` loops by key, but compares each key using that parent stamp.
Consequently one genuinely changed/reconstructed setting lends fresh
provenance to every stale setting beside it. The round-3 `scalars` versus
`watchState` split prevents playback from causing this, but does not isolate
one scalar setting from another.

### 13.2 Required wire and merge change

Introduce hot-document schema v2. The root marker, circle key, crypto envelope,
manifest format, paths, profile/resource maps, watch records, tombstones, and
graph sections do not change.

- Replace the scalar map's single conflict stamp with a bounded map of
  individually stamped entries: logical preference key → `{value, stamp}`.
  Reuse `WebDavSyncStamp` and the existing scalar type gate (`bool`, `int`,
  finite `double`, `String`, `List<String>`). Keep one canonical semantic
  digest for integrity/dirty detection only.
- Build each key against the last applied baseline. If its portable value is
  unchanged, preserve the exact prior normalized time and origin. If it is a
  genuine local difference, stamp only that key with the current accepted
  server-normalized time and local device ID. A changed outer digest never
  restamps an unchanged entry.
- Merge independently per key using
  `(normalizedTime, originDeviceId, valueHash)`. Different-key concurrent
  edits union; same-key edits remain deterministic LWW.
- Materialize/apply values exactly as today. Null and omission remain
  non-deleting; scalar removal is not invented here. `mdblist_sync_checkpoint_v1`
  stays local-only and cannot create or receive a wire stamp.
- The last-pushed semantic digest still suppresses no-op traffic. After all
  peers converge, rebuilding/rebroadcasting an identical map must preserve
  every entry stamp and stop writes.

This deliberately fixes cross-key freshness transfer. It does not add a
mutation hook to every setting writer: two devices genuinely changing the
same key while offline are ordered when those local differences are first
normalized/published, as in v1. True edit-time ordering would require a
durable per-key mutation journal and is outside this repair.

### 13.3 Existing-folder and rollback behavior

- The new reader accepts schema v1 and v2. A v1 scalar value is translated in
  memory to a stamped entry inheriting its legacy parent stamp; the source file
  is never rewritten in place. The next own-device publication writes v2.
- No folder reset, machine-key rotation, re-adoption, profile remap, or new root is
  required. Current v1 winners remain the migration starting point; after both
  devices upgrade, the user reselects any value already lost during the bug.
- A legacy client cannot understand v2 and may keep publishing whole-stamped
  v1 data. New clients may read it for migration, but correctness is not
  claimed while a legacy peer remains active. The status/diagnostic surface
  records a legacy-hot peer, and physical acceptance requires every device in
  the test circle to run the repaired build.
- Emergency rollback remains boot-safe: an older client skips the newer hot
  section under §7's newer-section rule, retains its local preferences, and
  must not fail startup or rewrite the root.

### 13.4 Scope and effort

| Piece | Days | Notes |
|---|---:|---|
| Scalar v2 model + bounded v1 reader | 0.25 | no envelope/root change |
| Per-key build, merge, materialize, digest | 0.25–0.5 | pure Dart |
| Engine/schema dispatch + legacy-peer diagnostic | 0.25 | no activation change |
| Regression fixtures + physical Koofr repeat | 0.25–0.5 | both directions |
| **Total** | **~1–1.5 working days** | focused correctness repair |

Expected production change: roughly 4–6 sync files and 250–400 lines before
tests. No provider integration, provider credential, profile registry,
database, playback, playlist, or MDBList behavior is intentionally changed.

### 13.5 Regression exposure

**Medium inside WebDAV hot sync; low outside it.** The risky boundary is the
hot schema transition and deterministic merge, not the Default Provider UI.
Specific hazards are accepting malformed/oversized stamped entries, losing a
new-schema key during v1 translation, accidentally treating null/absence as a
delete, restamping `List<String>`, or allowing a local-only MDBList checkpoint
onto the wire. All are pure-model fixtures. Mixed old/new devices remain the
only operational limitation and are called out rather than silently claimed
safe.

### 13.6 Acceptance gates

- Exact regression: establish the same scalar baseline on A/B; A changes
  Default Provider and publishes; B changes a different scalar and publishes
  later. Both changes survive and both devices converge.
- Repeat in reverse (Android → macOS) and with `none`, Torbox, Real-Debrid,
  Premiumize, and AllDebrid values; reopen the page to prove persisted state,
  not a cached selection.
- Two devices change different scalar keys offline: union both. Two devices
  change the same key: deterministic per-key LWW on every merge order.
- Changing one key leaves every other key's complete stamp byte-identical.
  Rebuild, restart, peer rebroadcast, and an unrelated `List<String>` change
  cannot advance it.
- Legacy v1 golden document reads into per-key entries, converges with v2,
  and upgrades through a new content-addressed section without touching the
  root or requiring re-adoption. Newer/malformed schema remains fail-closed.
- Null/omitted values never delete local state; the MDBList checkpoint remains
  local-only and does not restamp any scalar. Existing playback, playlist,
  tombstone, and lossy-twin suites are byte-for-byte behaviorally unchanged.
- Four-device convergence reaches identical documents and then performs zero
  further section/manifest writes.
- Physical Koofr gate: upgraded Mac publishes Default Provider; upgraded
  Android pulls it, then publishes an unrelated setting without reverting it;
  repeat Android → Mac. Record authenticated remote value + per-key stamp from
  both manifests in the test note.

## 14. v3 — Live library sync for per-record database families

Implemented 2026-09-03 overnight (rounds 2a `2f1ddfb4`, 2b `8f81d3ce`,
2c `be01a978`, compaction fix `feb07eae`). Everything below is shipped
behavior, recorded here as the design of record.

### 14.1 Scope

Synced live, per record, under the same stamped-LWW rules as hot scalars:

- IPTV personal state: hidden categories (`hidden_groups`), manual category
  arrangements (`category_manual_orders`), per-category channel arrangements
  (`iptv_category_channel_orders`), VOD watch history/continue watching
  (`iptv_watch_history`), video resume (`video_resume`), custom-list metadata
  (`iptv_lists`) and Favorites/custom-list membership
  (`iptv_list_channels`).
- Debrify TV: channels with their keywords (`tv_channels` +
  `tv_channel_keywords`, one record), and per-channel torrent hash pools
  (`tv_cached_torrents`) — the pool is the channel's playable inventory.

Excluded by design: IPTV catalogs/EPG (each device re-downloads its
playlists), `tv_keyword_stats`, `tv_channel_cache_state`
(both rebuildable device-local caches).

### 14.2 Wire placement

A per-profile `library/<circleProfileId>` section (schema 1): one map of
stamped nullable leaves, routed through the large-section path. Bounds are
64 MiB / 100k leaves, fail-closed on build and apply — an over-bound
library refuses the cycle visibly (status + diagnostics); it never
truncates or silently skips. Record keys never carry URLs, headers, or
group names in the clear:

- `tv/ch/<b64(channelId)>` — channel + keywords + desired number.
- `tv/pool-gen/<b64(channelId)>` — the channel's current pool generation
  (generation id rides the sidecar `aux` and the leaf).
- `tv/pool/<b64(channelId)>/<lowerInfohash>` — one pool row
  {generationId, name, sizeBytes, keywords, rank}. Scrape metadata
  (seeders, dates, sources_json) is deliberately not carried.
- `iptv/order/<circleResourceId>/<sha256(group)>`,
  `iptv/watch/<circleResourceId>/<sha256(url)>`,
  `iptv/list/<base64url(customListId)>`,
  `iptv/list-ch/<base64url(listId)>/<sha256(url)>`,
  `resume/<circleResourceId-or-_>/<sha256(resumeKey)>`,
  `catalog/hidden/<circleResourceId>/<variant>/<sha256(group)>`,
  `catalog/category-order/<circleResourceId>/<variant>` with
  variant ∈ {local, m3u, xc-live, xc-vod, xc-series}. Raw URLs/headers may
  appear only inside sealed leaf VALUES, never in keys or diagnostics.

### 14.3 Sidecar provenance

Both `debrify_tv.db` and `iptv_catalog.db` gained
`webdav_sync_record_state(kind, owner_key, item_key, updated_at_ms,
origin_device_id, normalized, deleted, aux)` plus `webdav_sync_meta`
holding a monotonic `mutation_revision` (seeded '0' via INSERT OR IGNORE
in create and upgrade paths; every stamped writer bumps it in the same
transaction).

Mutation origins: `user | syncApply | migration | maintenance | rollback`.
Only `user` stamps and notifies the scheduler; the revision advances on
user writes and on any apply batch that touched rows (that second bump is
what lets the next build observe a fresh fence).
Retention prunes (watch history 100 rows), cache evictions, failed-edit
restores, migrations, and "Reset app data" are silent — a cap or a local
wipe must never mint a circle-wide deletion. Deletions that ARE user
intent write `deleted=1` tombstone rows (channels: per-channel tombstones
on delete and clear-all).

`debrify_tv.db` schema v10 seeds migration-origin `iptv_lists` stamps for
existing custom lists and `iptv_list_channels` stamps for every membership,
including Favorites, using `updated_at` / `added_at` as their initial times.

### 14.4 Pool generations

Pools replace atomically, never row-by-row: every user pool save mints a
fresh generation id (`tv/pool-gen` record), publishes the full pool under
that generation, and peers materialize only pool leaves whose generationId
matches the winning generation record — stale rows from a losing
generation are inert and cleaned by the next generation apply. Explicit
pool removal publishes one empty generation. There are no per-row pool
tombstones.

### 14.5 Apply semantics

- Revision-fenced: apply re-reads `mutation_revision` in its transaction;
  a concurrent local user write turns the batch into a typed benign
  conflict that clears pending state and schedules an immediate follow-up.
- Channel numbers canonicalize deterministically on every device: winners
  sort by (desired number, channel id) and take the next free slot;
  occupied numbers are vacated to temporary values first so exchanges
  cannot trip the UNIQUE constraint mid-transaction.
- Custom-list positions canonicalize by `(position, listId)` into a sequential
  custom-list order; Favorites keeps its permanent local parent row. A custom
  list tombstone suppresses all of its member leaves, and local foreign-key
  cascade removes the materialized memberships.
- Change detection is sidecar-stamp AND physical-row: a matching channel
  stamp with a missing physical row still materializes, and a matching
  pool-generation stamp is additionally probed by row count (first-join
  after the §1 compaction carve-out; equal-count content divergence is
  outside the probe and accepted). Compaction additionally strips the
  `tv_channels`/`tv_pool_generation` sidecar rows when it drops those
  tables (`feb07eae`), so adopted snapshots never inherit stamps for rows
  they do not contain. The library section is now the authoritative
  carrier for Debrify TV: a joiner whose bootstrap omitted the TV tables
  receives full channels and pools on its first cycles.
- Identity: catalog families map through (circleResourceId, variant);
  records for unmapped resources are retained, not dropped or misapplied.
- Unknown record families merge and republish verbatim (forward compat);
  they are never applied and never stripped.

### 14.6 Propagation and UI

User library mutations ride the same 2s coalescing local-change window and
durable intent as hot scalars (`webDavSyncLibraryLogicalKey`). Applied
batches dispatch family-scoped refreshes: `tv/ch` + `tv/pool` invalidate
the mounted Debrify TV screen through a dedicated MainPageBridge hook;
`catalog/*` and `iptv/*` reuse the IPTV catalog/source signals; watch and
resume records fire the playback-data notification. UI callbacks are
best-effort and can never fail a committed batch.

`iptv/list` and `iptv/list-ch` coalesce onto the IPTV media-store list revision
so mounted Favorites/custom-list surfaces reload once per applied batch.

### 14.7 Adversarial review outcome (2026-09-04 night)

Nine findings triaged; four produced changes, five were rejected with the
reasoning recorded here so they are not re-litigated:

- **Fixed — device-local reset minted circle-wide deletions.** The legacy
  (non-profile-mode) "Reset app data" ladder recorded playback deletions,
  finished-movie/continue-watching/playlist(+favorites) tombstones, and
  resume tombstones with user origin. Every clear in that ladder now takes
  `recordSyncDeletions: false` / maintenance origin, and a maintenance
  resume clear also drops its live sidecar stamps so the circle's records
  re-materialize after the wipe. Profile-mode resets were already safe:
  they swap whole data generations, so stamps travel with rows. The
  explicit settings "Clear playback data" action keeps deliberate
  cross-device deletion semantics.
- **Fixed — stamp collisions under clock steps.** All three mint paths
  (TV mutation, media store, catalog DB) stamp through a per-clock
  monotonic floor (`WebDavSyncMonotonicStamp`): a backwards NTP step can no
  longer mint two different mutations with one identical (time, origin)
  stamp, which closes the mixed-generation LWW tie-break edge.
- **Fixed — exact generation stamp masking missing pool rows.** The pool
  apply gate now row-count-probes `tv_cached_torrents` when the sidecar
  stamp matches; a divergent pool re-materializes.
- **Fixed earlier the same night** — compaction strips the TV sidecar
  stamps it orphans (§14.5).
- **Rejected: duplicate-URL collisions across two granted resources.**
  Two active playlists sharing one stream URL share one physical
  history/resume row; merge order is deterministic, so devices converge on
  the same winner. Accepted as a bounded quirk, not divergence.
- **Rejected: partial intra-file row loss republished under an old
  stamp.** Physical rows and sidecar stamps live in one SQLite file and
  move atomically; partial intra-file loss is outside the durability
  model (whole-file loss takes stamps along). Pool families additionally
  self-heal via the count probe.
- **Rejected: library mutations waiting in the 60s playback window.**
  Identical to how every non-checkpoint local change behaves during
  playback; consistency is the design.
- **Rejected: destructive downgrade.** `onDatabaseDowngradeDelete`
  pre-dates v3 (shipped with v6) and is a deliberate anti-wedge choice.
- **Rejected (deferred): unknown sidecar kinds from an adopted
  newer-version snapshot are not republished by an older binary.** The
  records stay intact locally and publish after the app updates; wire
  documents already round-trip unknown families.
- **Accepted residual — stamp normalization can collapse the monotonic
  floor.** Local stamps ahead of server time clamp to `serverNowMs`
  (second-resolution) at build, so two mints from one device could
  normalize identically — but only when two full publish cycles land in
  the same server second, which cycle latency prevents in practice; the
  worst case is one mixed pool that self-heals on the next edit.
- **Known growth bound (documented, not fixed):** watch-history and
  resume leaves never tombstone from retention, so the library section
  grows monotonically toward the 100k-leaf / 64 MiB fail-closed caps
  (years at personal scale; leaves are ~a few hundred bytes). When a cap
  is hit, the build refuses visibly with an audited message and the
  durable intent retries at the saturated 2-minute backoff with no
  network cost. A deterministic post-merge age trim for watch/resume
  families is the designated follow-up if anyone approaches the bound.

### 14.8 Lists round adversarial triage (2026-09-04)

Seven findings on the favorites/custom-lists round; five fixed, two
rejected with reasoning:

- **Fixed — merge-time canonicalization was unstable.** Rewriting winner
  values under unchanged stamps broke idempotence (proven with divergent
  digests). Both merge-time canonicalizers are gone: wire documents keep
  desired numbers/positions byte-for-byte; the SQLite materializer alone
  assigns collision-free physical values, and sync apply retains the
  desired value in sidecar `aux` so the build republishes the stamped
  desired value, never the physical assignment. A user edit resets aux,
  adopting the visible value under a fresh stamp.
- **Fixed — malformed leaves quarantined**, not thrown: full validation
  before any typed read; invalid leaves skip materialization with a
  content-free diagnostic and stay in the merged document.
- **Fixed — wire header budget**: member httpHeaders over 2048 encoded
  bytes are omitted from the sealed value (row still syncs; local
  playback keeps local headers).
- **Fixed — idempotent legacy import**: the import pre-loads existing
  sidecar states and never overwrites one (a tombstone written between
  import attempts survives replay); a failed prefs.remove is audited.
- **Fixed — list id entropy**: 64 secure random bits.
- **Rejected: row-granularity LWW** (a reorder can beat a concurrent
  rename of the same row): consistent with every v3 family — channels
  carry name+number+keywords under one stamp too. Self-corrects by
  redoing the edit.
- **Rejected: reconcile-alias vs unfavorite race** (an unfavorite of a
  URL being renamed can resurface under the new URL): rare, requires the
  race inside one propagation window, and one more unfavorite sticks.
  Keying by canonical channel identity was judged a redesign not worth
  the migration.

### 14.9 Debrify TV foreground-only carve-out (2026-09-04)

This subsection supersedes the Debrify TV placement and propagation parts
of §§14.2, 14.5, and 14.6. The IPTV, history, resume, stamp, origin, merge,
pool-generation, and materialization contracts above are unchanged.

- Debrify TV records live in the per-profile `tv-library/<circleProfileId>`
  section. It uses the existing schema-1 library document, shared codec,
  compression and large-section path, with the existing 64 MiB / 100k-leaf
  fail-closed caps. The ambient `library/<circleProfileId>` build emits no
  `tv/ch`, `tv/pool-gen`, or `tv/pool` records.
- Ambient apply ignores TV records found in a peer's old main library
  section and emits one content-free audited diagnostic per affected merge.
  Those stale records are also excluded from the merged publish target, so
  the first post-update ambient republish naturally replaces the old main
  section with a TV-free document.
- TV user writers retain the same sidecar stamps, mutation revisions,
  origins, tombstones, and pool generations, but no longer notify the
  scheduler or create durable ambient intent. In the same transaction they
  set a lightweight per-profile `tvChangesPending` marker and advance its
  pending revision. A completed manual sync clears the marker only if no
  newer TV user mutation raced the operation, and records its completion
  time.
- The only operation that reads, applies, or publishes TV wire records is
  **Sync Debrify TV now** in WebDAV settings. It runs in the foreground,
  shares ordinary-cycle serialization, and refuses inactive bindings,
  pending first joins, and concurrent cycles. Its stages are Reading,
  Merging, Applying, and Publishing; Stop is checked between stages. A
  stopped run leaves committed work consistent, consumes no peer reference
  until publication succeeds, and a later run resumes normally. Unchanged
  peer TV sections reuse the ordinary per-device/section reference skip.
- The settings block shows the pending hint and last successful completion
  time. The modal progress surface is blocking while the foreground
  operation runs and exposes the stage-granular Stop control. Product copy
  says Debrify TV syncs only when run manually and calls out running it
  after connecting another device or importing channels.
- The ambient library has a separate 20,000-leaf soft cap. Both local build
  and final merged-publish checks fail closed with an audited, visible
  error. The TV section retains the 100k-leaf / 64 MiB bounds. This makes
  ambient history/resume growth visible long before it can become a
  human-scale performance hazard while leaving the deliberately large TV
  inventory on its explicit foreground path.

## 15. Login-first setup & single circle authority

This section is the normative setup amendment for WebDAV Sync. Where older
passages describe selecting a Cloud WebDAV account/folder or entering a sync
passphrase, this section supersedes them.

- Sync owns a dedicated login session and never registers it in the Cloud
  WebDAV registry. The login result exists only in memory until the sync
  binding store seals it. Koofr uses the pinned endpoint
  `https://app.koofr.net/dav/Koofr/`; Custom accepts HTTP(S) and keeps the
  explicit insecure warning for HTTP.
- The folder is always `Debrify` below the effective endpoint, yielding
  `Debrify/debrify-sync/...`. Setup never presents a folder picker. The normal
  Cloud WebDAV add/browse flow is unchanged.
- `circle.authority` is the only existence/authority object. Its strict JSON is
  `{"version":1,"marker":"<base64 sealed marker>","syncPassphrase":"<string>"}`.
  It rejects unknown/missing keys, unsupported versions, invalid secrets,
  malformed JSON, markers over the existing 64 KiB root-marker limit, and
  whole objects over 96 KiB without echoing content. New secrets are 32 secure
  random bytes encoded as 43-character unpadded base64url. The embedded
  marker's Argon2id + AEAD wire format and AAD are unchanged.
- Setup authorization captures an Admin session and revalidates before each
  send/commit without requiring a Cloud connection resource ID or revision.
  The merged-authority probe remains GET-only; the authenticated legacy
  compatibility upgrade is the sole inspection-time write exception described
  below. The shared connect controller owns
  inspect → configure → initialize/connect and reports cancellation, Active,
  adoption-finishing, and pre/post-handoff failures. UI confirmation and
  runtime pause/resume remain with the caller. Onboarding uses the same
  controller and acknowledges its durable completion intent only after the
  profile-scoped setup-complete write succeeds.
- New-root activation proves the collection exists, then performs only a
  linearizability smoke check: unconditional PUT of a random sentinel followed
  by an exact GET and best-effort DELETE. A definite missing/mismatching GET is
  a typed non-linearizable-store failure. Transport/no-response failures,
  401/403 credential failures, 408/429/5xx responses, and response-drain failures are bounded-retry
  inconclusive outcomes. A failure after response headers retains that HTTP
  status in redacted diagnostics. No path, body, error object, or secret is
  logged. Koofr passes because overwriting and ignored `If-None-Match` are not
  disqualifiers.
- Activation reads the single authority before candidate use, persists only
  the candidate's sealed inner marker locally (the secret remains in the
  device-sealed binding), deterministically wraps them for comparison, uploads
  and verifies the complete seed, and
  writes the authority last. It always reads the authority after its PUT. An
  exact match wins; a different valid/authentic authority is adopted. The
  existing secret-reseal and reset journal atomically preserve WebDAV login
  and lifecycle while invalidating losing candidate bytes, device identity,
  engine state, and device-ID-derived sentinels. Malformed standing bytes fail
  closed and are never overwritten. Conditional create may be sent as an
  optimization but its response never decides ownership.
- Concurrent-root follow extracts the secret and sealed marker from the same
  winning object, persists the secret, resets the losing candidate, and only
  then enters existing-root adoption. Discovery and ordinary cycles pin and
  compare SHA-256 hashes of the exact `circle.authority` bytes. Local pins
  persist only the encrypted inner marker plus `authorityContentHash`; the
  runtime opens that marker using the device-sealed binding secret. Legacy
  marker-only pins hash the legacy marker itself. Assembled authority bytes
  are never persisted in preferences.
  Existing bindings are not relocated, including the deployed Koofr `/dav/` +
  `Koofr/Koofr sync` shape with no keyfile.
- Credential repair asks only for username/password, then reads
  `circle.authority` from the binding's stored endpoint/folder. Missing-state
  reconnect uses the same stored location. If authority is absent, the
  read-only compatibility path probes legacy `circle.json.enc` and
  `circle.key`. A marker-only repair uses the locally sealed secret; a keyfile
  supplies it where present. Only after authenticating the legacy marker does
  repair GETs the authority again and adopts an existing valid authority.
  Only a confirmed-absent GET permits provisioning with PUT + mandatory
  read-back. A simultaneous write is the accepted detected-replacement
  residual; this pre-PUT check does not prevent every overwrite. A different valid object is adopted; malformed bytes
  fail closed. Conditional create is never required. A crash after remote
  upgrade but before local repinning is recoverable because the embedded
  marker can exactly match the prior legacy pin.

Final contract: sync initialization requires a linearizable WebDAV object
store, not honest conditional creation. Koofr's confirmed behavior—an
`If-None-Match: *` PUT to an existing path returns 201 and overwrites—is
supported. Because marker+secret are one LWW register, all racing read-backs
observe a single internally consistent authority and losers use the existing
adoption ladder. A transient smoke-check result remains retryable; a definite
non-persisting/mismatching store is the only typed provider-capability failure.
Every failure diagnostic contains only step plus HTTP status or exception kind
and nulls the error object.

Residual, stated honestly: a device can finish and become Active just before a
long-paused concurrent first creator overwrites the authority. Its next cycle
compares the hash of the exact pinned authority bytes and raises `RootChanged`; the existing explicit
user-confirmed reconnect path authenticates the complete replacement, rotates its root-scoped
namespace, and re-enters adoption. The observed replacement is a complete
openable marker+secret, never a silent or unopenable split. Automatic adoption is forbidden: a replacement could be malicious. This
detected replacement window does not occur in sequential personal setup. An
eventually consistent store that fails read-after-write is rejected by the
smoke check; no finite client probe proves all possible multi-replica histories.

The accepted trust change is deliberate: because the at-rest secret sits in
the authority beside the encrypted data, encryption no longer protects the
user from the storage provider or any principal that can read the entire
folder. It still protects against isolated blob leakage, authenticates all
wire documents, and avoids an inner marker/KDF migration. A local automatic
sync safety backup and the server authority together are enough to decrypt
that backup; they must be treated as one recovery trust domain.
