# Debrify Cross-Device Sync over WebDAV — Implementation Plan

Status: M1 + M2 IMPLEMENTED on `webdav-sync` (2026-09-01); automated
acceptance gates pass. The version-pinned real-Nextcloud and physical-tvOS
checks remain manual release gates. M3–M6 are PLANNED + LOCKED. This plan was
revised through TWELVE review rounds — rounds 1–3, 5–8 and 10–12 external,
rounds 4 and 9 self; round 9 was the pre-lock consistency sweep, after which
the user locked the design. Rounds 10–12 arrived post-lock and refined ONLY
the M1/M2 acceptance criteria (§8) — the architecture is unchanged and stays
locked. There is no freeze claim: every later invariant below gets encoded as
an M4/M5 test before it is trusted.
Goal: everything the app considers "the user's state" — profiles, connections,
addons, playlists, favorites, settings, watch progress, source bindings —
follows the user across devices, via a user-supplied WebDAV server, encrypted
client-side, with no Debrify-run infrastructure. **Honest carve-out (round-6):
`debrify_tv.db` contents — Debrify TV channels, IPTV lists/favorites/watch
history, IPTV `video_resume` — transfer at JOIN and survive refreshes via
carry-forward, but do NOT sync continuously in v1. The UI must say so (§6);
this goal line must not oversell it. Playlists and playlist favorites are
prefs (`user_playlist_v1`, `playlist_favorites_v1`) and DO hot-sync.

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
pairings, OS grants, local paths, caches, download binaries) **with one
verified exception**: `DebrifyTvBackupOmission` (dropped `tv_channels` +
`tv_cached_torrents`) is durable user data, not cache. Rules:

- Sync graph exports NEVER use `compactDatabaseSnapshots`.
- If an export reports any DB omission or oversized skip, the graph push is
  **refused** and the previous graph section stays — a partial graph is
  never published.

`ProfilePreferencePortability` already classifies every pref: credentials
blocked (travel as sealed resources instead), device-local blocked,
`playback_state_v1` stripped of URLs/paths but **kept**, `series_source_*`
stripped of local pins but **kept**. We invent no new taxonomy. Ever.

### D2 — Adoption, not merge, for the graph
Cross-device profile identity is the only genuinely hard problem, so we
delete it: **a circle has one seed**. The first device uploads its graph;
every device that joins **adopts** it with explicit consent. We never merge
two pre-existing profile registries.

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
nor a badly stale snapshot. **Join flow = adopt bootstrap → immediately auto-apply the latest
graph revision (with copy-forward) → hot merge** — never a stale bootstrap
alone. Ongoing channel/favorites DB sync is v2 scope.

The trick that makes hot merge cheap: the concurrent-edit data **already has
intrinsic per-record timestamps** — `playback_state_v1` entries carry
`updatedAt` (LWW resolution already exists at `lib/services/storage_service.dart:3407`),
`SeriesSource` carries `boundAt`. Scalar settings don't conflict in practice,
so they get sub-section LWW with honest provenance (§4.1). No mutation-site
sweep, no per-key timestamp retrofit.

---

## 2. What we reuse verbatim (verified)

| Machinery | Where | Role in sync |
| --- | --- | --- |
| Full-state export | `lib/services/profiles/profile_package_service.dart:181` `exportAllProfiles` (+ additive `includeDatabases` / `includePreferences` flags — refresh graphs pass both false, §1 D3) | graph push payload |
| Atomic graph apply (ADDITIVE — see D2) | `lib/services/profiles/profile_restore_coordinator.dart:80` `restoreDeviceGraph` (staged publish, ghost-purge rearm at `:138`) + existing per-profile delete APIs as the prune companion | CircleAdoption flow |
| Encrypted envelope | `lib/services/profiles/portable_profile_package.dart:534` Argon2id(19MB, it=2 — sub-second) + AES-GCM, off-isolate, `probeFile`/`decryptFile` | at-rest crypto, reused as-is for the graph; small additive `sealSyncDocument`/`openSyncDocument` for hot docs using the same primitives + own AAD, but with a **circle-fixed KDF salt** (stored in `circle.json`) + per-file random AEAD nonces, so the key derives ONCE per cycle — the stock format's per-file random salt would force one 19MB Argon2id run per peer × section on every pull, colliding with the tvOS low-memory gate |
| Pref portability policy | `lib/services/profiles/profile_preference_portability.dart` | hot doc contents = `_exportPreferences` output — which is **private today** (`lib/services/profiles/profile_package_service.dart:387`); expose it additively (round-7). **Null rule (round-7):** `prepareValue` deliberately exports device-sealed IPTV execution state and malformed blobs as EXPLICIT NULLS (`profile_preference_portability.dart:51`) so a one-shot RESTORE clears them — but a recurring merge honoring nulls would erase local device state every cycle. The doc builder therefore DROPS null-valued entries; hot deletion travels only as tombstones |
| WebDAV client (protocol layer only) | `lib/services/webdav_service.dart` (PROPFIND, DELETE, basic auth) | transport; only PUT/MKCOL/GET-bytes are new. **NOT reused: `_authorize`** — it gates on the ACTIVE profile's `ProfileFeature.cloud` grant, which would break sync under non-admin/kid sessions. The engine holds its OWN device-level transport credentials (§5) |
| Credential storage | **`DeviceKeyProvider` (round-7 — supersedes round-6's SecretVault choice, which was WRONG):** the repo already ships a platform-native secret store — the `debrify/device_secret` channel backed by Android Keystore AEAD (`android/.../security/DeviceSecretCipherPlugin.kt`), Apple Keychain including a tvOS implementation (`tvos/Runner/AppDelegate.swift`), Windows DPAPI (`windows/runner/flutter_window.cpp:105`), and a Linux passphrase-wrapped vault (`lib/services/profiles/device_key_provider.dart:10`). The connection-resource secrets inside the very graph packages sync ships are ALREADY sealed with it; `SecretVault`'s "OS keystores unavailable" header is stale in scope | circle passphrase + engine transport credentials sealed via `DeviceKeyProvider.cipher` with sync-specific AAD. Two encoded caveats: the **Linux vault can be LOCKED** — the cycle defers until unlock, exactly as profile resources already do; and sealed values are **device-bound, non-exportable** — correct, since these secrets must never travel. `SecretVault` (obfuscation-grade, `lib/services/secret_vault.dart:12`) is NOT used for sync secrets |
| Single-flight + scope-capture patterns | remote fast path (`_applyingRemotePayload` guard, captured authorization) | engine concurrency discipline |
| Admin authorization for graph ops | remote receiver's pattern for `ConfigCommand.profileGraph` (`lib/services/remote_control/remote_command_router.dart:1088`) | graph build/apply authorization |

**Not reusable (verified):** there is no stable per-install device ID —
`RemoteControlState._generateDeviceId` regenerates per start
(`:206`/`:305`) and `SecretVault`'s hardware ID is private to the vault.
The engine **mints and persists its own sync device UUID** at enrollment.

---

## 3. Server layout — dumb-server-proof by construction

```
<user-chosen folder>/debrify-sync/
  circle.json.enc                     # IMMUTABLE after seed: circle id, created-at,
                                      #   schema floor, circle KDF salt, key-check
  pre-join-backups/                   # automatic safety backups, not synced
  devices/<deviceId>/manifest.enc     # THE commit record: clockOffsetMs vs server
                                      #   Date + circleId maps (profiles+resources)
                                      #   for the current graph revision + this
                                      #   device's graph SCHEMA CLAIM (ratchet
                                      #   input, §5) + list of {section,
                                      #   contentHash, semanticDigest, updatedAt,
                                      #   schemaVersion, size}
  devices/<deviceId>/sections/<contentHash>.enc   # immutable, content-addressed blobs
```

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

**Threat model:** the server is untrusted for confidentiality and integrity
(AEAD per file; AAD binds deviceId + section name + schemaVersion so blobs
can't be spliced across devices/sections) but trusted for availability and
— documented, bounded in BOTH directions (round-6) — for **time** (§4.4):
future-stamped records clamp at publish time, and the server's `Date` is
held to a per-device monotonic high-water mark, so neither a forward-lying
nor a backward-jumping server clock can bury genuine edits. Version vectors
deferred to v2 unless practice proves this insufficient. Server-side
rollback of a peer's manifest is detected cheaply: remember each peer's
last-seen manifest timestamp, ignore regressions, log to privacy log.
Transport: Basic credentials go only to the enrolled origin — the sync
client never follows cross-origin or scheme-downgrade redirects (M1), and
explicit `http://` endpoints are permitted but labeled insecure wherever
a server is configured or chosen — the WebDAV config UI from M1, the
Migrate destination picker in M2, enrollment in M3 (round-11 fixed the
"at enrollment only" wording, which would have shipped M1+M2 unlabeled).

---

## 4. Merge semantics (the one new module — pure Dart, exhaustively unit-testable)

The hot doc has **two independently-stamped sub-parts** (round-3 fix):
`scalars` and `watchState`, each with its own semantic digest and its own
`updatedAt` that advances ONLY when that digest changes. A playback write
therefore never restamps unchanged settings — without this, a device that
missed a settings update would republish its stale scalars under a fresh
timestamp after any unrelated playback change, silently reverting the
newer settings. **Cycle order is pull → merge → apply → push**, so a device
always merges the world before publishing.

Given local state + all peers' hot docs for a profile:

1. **Scalars: sub-section LWW with key-union.** Winner = newest
   `scalars.updatedAt` (adjusted, deviceId tiebreak); keys absent from the
   winner but present in other docs are retained from the newest doc
   containing them (protects new-in-schema keys from being dropped by an
   older writer's win). Documented trade: two devices editing settings
   within one debounce window → newest wins. Benign, re-doable.
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
   re-set RTC or fresh enrollment passes immediately or within two cycles;
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
own minted-and-persisted sync device UUID (see §2 — no existing ID is
stable).

**Transport authority is engine-owned (round-3 fix):** at enrollment the
engine copies the chosen WebDAV endpoint + credentials into device-level
sealed storage (`DeviceKeyProvider`, §2 — round-7) and performs all sync
HTTP with them directly.
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
and recommending the circle instead.

Triggers: app launch (post-unlock), foreground, playback stop (hot push),
app background (hot push), every 15 min while active, manual "Sync now".
Debounce 45s. Suppressed during active playback on TV and under the tvOS
low-memory gate. Graph section rebuild at most every 6h or on manual sync —
hot docs are the frequent traffic (and with DB snapshots AND preference
sections both out of the refresh graph — §1 D3, rounds 2+8 — ordinary
watching, favoriting, and settings tweaks never dirty it).

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
device's SERVER doc from resurrecting deletions. **Tombstones are
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
into the actor's own section, then deletes the directory. Its LOCAL copy is handled
by the **dormant-rejoin rule**: a device whose `lastSuccessfulSync` is
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
has two halves: **Sync** (the circle — everything below) and **Migrate**
(one-shot WebDAV backup/restore, M2). Contents:
- Server: pick from existing `WebDavConfig` list (reuse; creds already
  sealed as connection resources) + folder selection via a dedicated
  DPAD-safe picker MODE (round-10: the existing WebDAV screen is a media
  browser whose taps PLAY files —
  `lib/screens/webdav/webdav_files_screen.dart:977` — it gains a picker
  mode; it is not reusable as-is). Enrollment copies the endpoint into
  engine-owned storage (§5).
- **Start a circle** (this device seeds): choose passphrase (min 8, matches
  backup rules) → engine writes `circle.json.enc` **create-only (round-6):**
  attempt `If-None-Match: *`, but never trust the server honored it — read
  back and byte-verify. A mismatch means another device seeded
  concurrently; abort THIS seed and offer to join the existing circle
  (two racing seeds would silently fork the "immutable" circle root).
  **Round-7 — read-back alone still leaves a small two-writer race on
  servers that ignore `If-None-Match`, and capability can't be probed
  reliably (refusing such servers would kill rclone/dufs setups —
  rejected). So every device PINS the `circle.json.enc` bytes it
  seeded/joined with and re-verifies them on each cycle's first GET: a
  racing fork becomes a loud "another circle exists on this server" hard
  error one cycle later, never a silent split** → first
  bootstrap/graph/hot push. Requires an Admin session.
- **Join a circle**: Admin session required (adoption calls
  `restoreDeviceGraph`) → enter passphrase → key-check against
  `circle.json.enc` → explicit consent screen: *"Replace this device's
  profiles & connections with the circle's? Local profiles on this device
  will be removed."* → automatic safety backup (below; **probe-verified by decrypt-check before
  any destructive step runs** — round-7) → CircleAdoption of the bootstrap
  → auto-apply latest graph revision (copy-forward included) → hot merge.
- **Pre-adoption safety net:** before adoption, the engine automatically
  writes ONE full local `deviceGraph` backup to `pre-join-backups/` (or
  local file), **encrypted with the circle passphrase** — invariant 15
  carves out this one sanctioned reuse: the backup lives in the same trust
  domain (same server, same owner) and the alternative is either an extra
  passphrase prompt at the worst moment or an unrecoverable backup.
  Per-orphan one-tap exports are NOT possible — `exportProfile`
  hard-requires the acting profile to BE the exported profile, and child
  profiles cannot hold backupRestore at all. Restoring an individual
  pre-circle profile from the safety backup is a manual flow in v1;
  automated carry-in is the v2 union-merge feature.
- Status card: last sync, per-device list (from manifests), Sync now,
  clock warnings, "waits for an Admin session" / prune-pending block when
  applicable, and the v1 carve-out stated plainly (round-6): *"Live TV
  channels, IPTV lists, favorites & history transfer when a device joins —
  they don't sync continuously yet."* The UI never promises what §1's
  carve-out excludes.
- **Forget device** (round-3 rename): first materializes the device's
  unexpired tombstones into the actor's own section (§5, round-6), then
  deletes the device's server directory and drops it from the union —
  presented explicitly as bookkeeping for an already-decommissioned device. It is NOT revocation: an installed device
  still holds the WebDAV credentials and circle key. The dialog says so and
  points to real revocation (change the WebDAV password on the server;
  circle re-key is a v2 feature).
- Graph-changed prompt: quiet badge + dialog on next app open, never
  mid-playback; declined revisions never re-prompt (§5).

**Migrate half (M2):** "Save backup to WebDAV" + restore-from-WebDAV
browser — living HERE in **Sync and Migrate**, NOT on the Backup & Restore
page (user decision 2026-09-01; the existing Backup & Restore page stays
untouched). Fixes TV backup (no `ACTION_CREATE_DOCUMENT` there) and
exercises the full write path before sync ships. This means the Sync and
Migrate section EXISTS from M2, with only the Migrate half populated; the
Sync half arrives with M3's enrollment + status card.

---

## 7. Version skew & compat rules (carrying the tvOS boot-loop lesson)

- Every section carries `schemaVersion`; `circle.json` carries the schema
  floor ONLY — the graph ratchet is DERIVED from manifest claims, never
  stored centrally (§5; round-6 removed the contradiction where this line
  still said `circle.json` carries it).
- Reader supports `[floor..current]`; a **newer** section is skipped and
  preserved — never deleted, never overwritten, never blocks other sections.
- Graph revisions BELOW the ratchet are never applied (§5); hot-doc scalar
  merges use key-union (§4.1) so an older writer's win cannot drop
  newer-schema keys.
- Old devices keep pushing their own sections under their own directory —
  per-device dirs mean skew can never clobber newer data on the server.
- Graph payloads inherit `PortableProfilePackage` versioning
  (`oldestSupportedVersion` 3) — already tolerant.

---

## 8. Milestones (each independently shippable, tested, flag-gated)

| # | Deliverable | New code | Days |
| --- | --- | --- | --- |
| M1 | WebDAV protocol client: `putBytes`/`uploadFile` (streamed from disk) with MKCOL-on-409 for parents, `getBytes` (capped)/`downloadToFile` (streamed), `exists`; typed error contract; **transport hardening (round-6):** the sync client sets `followRedirects = false` and refuses cross-origin / scheme-downgrade redirects (the current client follows redirects with `dart:io` defaults, which replay the Basic credentials at the new location; `_baseUri` upgrades only scheme-LESS URLs — an explicit `http://` goes out as-is, `lib/services/webdav_service.dart:186`); explicit `http://` stays allowed but is labeled insecure in the WebDAV server config UI from M1 onward (round-11; LAN Nextcloud/rclone reality — hard-requiring HTTPS was rejected); full acceptance criteria below (rounds 10–11) | ~400 LoC protocol client + tests | 1–1.5 |
| M2 | Backup to/restore from WebDAV (phone + TV UI) — lands in the NEW **Settings → Sync and Migrate** section ("Migrate" half), NOT on the Backup & Restore page (§6); acceptance criteria below (round-10) | transport-neutral backup entry points + picker mode + new settings section | 1.5–2 |
| M3 | Engine core: circle create/join enrollment (create-only seed + read-back verify + **local `circle.json` pin re-verified each cycle**), engine-owned transport creds + **passphrase sealed via `DeviceKeyProvider` with sync AAD (round-7; Linux locked-vault deferral)**, sync device UUID, layout, manifest protocol, semantic digests + ID canonicalization, `sealSyncDocument` (circle-fixed salt), clockOffset capture + server-`Date` monotonic high-water mark + **offset-delta damping**, **input bounds: doc/manifest size caps, peer-count cap, deviceId charset restricted for server paths, pinned hash algorithms (round-7)**, status UI skeleton | engine service + enrollment UI | 3 |
| M4 | Hot-state sync: deletion-path audit (**normative** — ships a test matching audited APIs to helper call sites) → tombstone helpers + replication + pending-until-published, two-part hot doc with `origin` stamps, merge module (pure functions, heavy unit tests: LWW + key-union + deterministic tie-break, alias-keyed playback unions + order stamps, completion diff-stamping, tombstones + cutoff exemption, dormant-rejoin, last-pushed dirty compare + convergence-stops-traffic, publish-time clamp, CW re-cap, **null-dropping doc build + never-delete-on-null apply, tombstone horizon from first publication — round-7**; **playlist per-item union by `computePlaylistDedupeKey` + diff-stamps + tombstones + order value, lossy-twin projection-equality rule — round-8**), `_exportPreferences` exposed additively, **scope-captured BATCH apply op (one tvOS checkpoint + one native projection — round-7) guarded by a persisted pending-apply target (round-8)**, triggers | merge module + helpers + glue | 5–5.5 |
| M5 | Graph tier: `includeDatabases` + `includePreferences` flags (structure-only refresh graphs — round-8) + restore-report resource-ID map (additive coordinator changes), omission-refusal rule, **pref carry-forward with resource-ref remap at refresh (round-8)**, **mode-scoped prune guards (join = snapshot-gated, refresh = pair-gated — round-8)**, CircleAdoption flow in round-7 order (**intent + pre-restore snapshot + probe-verified backup** → restore → phase record → drained DB copy-forward with **temp+rename placement and `IptvCatalogDb.closeScope()`** → remap → local-state carry-forward (DB-file-excluding) → handoff with **target open-gate** → grant-revoking + artifact-detaching mapped prune, quarantine + **graph-push block while prune-pending**; crash recovery = current-minus-snapshot rollback), circle IDs for profiles AND resources minted by any pusher, **graph arbitration by section time, heartbeat by manifest time (round-7)**, bootstrap regeneration triggers (profile-set change + daily-if-changed), join = bootstrap→latest-graph, prompted refresh + declined-revision persistence + derived schema ratchet, Forget device (tombstone materialization first) | flows + glue | 5–5.5 |
| M6 | Device-matrix hardening: phone ↔ Mi Box ↔ tvOS ↔ desktop passes, tvOS memory/path audit (sync state in Caches-safe paths; passphrase + creds sealed via `DeviceKeyProvider` — on tvOS that IS the Keychain after all, round-7 superseding round-6's SecretVault wording; nothing added to the 768KB recovery snapshot), soak | fixes | 1–1.5 |

### M1/M2 acceptance criteria (rounds 10–12 — implementation-spec reviews;
the design lock is untouched)

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
  result, and every response surfaces `Date` and `ETag` — M3's
  create-only seed and clock-offset capture both depend on them.
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
- The insecure-`http://` label ships HERE, not at M3 enrollment: M1+M2
  are independently shippable and can already send Basic credentials to
  an explicit `http://` endpoint. **Its M1 surface is the existing WebDAV
  server configuration UI (round-11); M2 repeats it in the Migrate
  destination picker; M3 enrollment inherits it.**
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
  pressure; the broader memory audit stays in M6.**
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
  was considered and TRIMMED — that atomicity belongs to M3's manifest
  protocol, not manual backups.
- **Temp hygiene + regression (round-11):** all staging uses private
  temporary storage with `finally` cleanup on EVERY exit — success,
  cancellation, wrong passphrase, oversize, network failure; and
  regression tests prove the local-file backup/restore path is unchanged
  by the transport-neutral refactor.
- The "Sync and Migrate" section costs what a settings section costs in
  THIS codebase: adaptive + TV index-based layouts, the settings-search
  registry, DPAD focus wiring, and their tests (the nav-index-audit
  lesson).

**Total v1: ~17–19 focused days** (round-6 re-estimate 16–18 up from 13–15:
the crash-ordered adoption flow, local-state carry-forward, prune
containment, tombstone delivery guarantees, and determinism hardening are
real scope, not polish; rounds 7–8 were line-level deltas absorbed within
it; round-10's honest M1/M2 criteria add the final day). M1+M2 is the
first shippable slice (~3 days); M3+M4 is the daily-value core; M5+M6
completes "everything".

### Explicitly deferred to v2 (do not scope-creep into v1)
- Silent graph steady-state: per-category **set-reconcile** diff apply through
  the remote fast-path handlers (adds deletions-propagate; removes the prompt
  and the concurrent-Admin lost-edit trade).
- **Ongoing `debrify_tv.db` sync** (channels, IPTV favorites/lists, TV
  history): needs record-level treatment, not snapshot replace. v1 carries
  it at join and preserves it across refreshes via copy-forward.
- **Circle re-key** (rotate passphrase → true device revocation).
- **Union merge at join**: automate carrying a joining device's unique
  profiles into the circle as additional profiles. NOTE: **identity merge**
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
2. **Never publish a partial graph**: compact mode never used for sync;
   any export omission/skip refuses the push and keeps the prior section.
   **Hot docs share the posture (round-9): a doc exceeding the M3 size
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
4. **Adoption model**: never attempt to merge two pre-existing registries.
   Joining always chooses: adopt circle, or (first device only) seed it.
   The pre-adoption full-graph backup is always written first.
5. **Per-device server dirs only** — no device ever writes another's files
   (Forget-device cleanup of a removed device's directory is the sole,
   explicit exception).
6. **Manifest-last, content-addressed, hash-verified** — the commit protocol.
   Never overwrite a section blob in place. Dirty detection compares
   SEMANTIC digests of canonical plaintext with circle-ID normalization,
   never sealed bytes and never local IDs — **against the device's own
   last-PUSHED digest only**. The adopted-digest echo-kill is REMOVED
   (round-6): every device republishes its merged union so state outlives
   its original author's manifest; convergence, not suppression, ends the
   traffic. Every device **pins its `circle.json.enc` bytes** and
   re-verifies them on each cycle's first GET — a forked circle root is a
   loud hard error, never a silent split (round-7).
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
13. **Credentials only ever travel inside the encrypted graph package** —
    hot docs are portability-filtered prefs, which already exclude them.
    Sync transport creds + circle passphrase are engine-owned,
    device-level, sealed **via `DeviceKeyProvider` (platform keystore —
    round-7), never SecretVault**; a locked Linux vault defers the cycle.
14. **LAN-only servers degrade silently.**
15. Backup passphrase and circle passphrase are separate concepts in UI copy
    (same rules, different lifetime); never auto-reuse one as the other —
    **single sanctioned exception: the automatic pre-adoption safety backup
    encrypts with the circle passphrase** (same trust domain; the
    alternative is an unrecoverable backup or a hostile extra prompt).
16. **"Forget device" is bookkeeping, not revocation** — the UI must say so.

## 10. Open product decisions (small, non-blocking — defaults chosen)

- Naming: the settings entry is FIXED — "**Sync and Migrate**" (user
  decision 2026-09-01, no longer open). Within it, the circle feature's
  branding defaults to "**Sync Circle**" (vs "Device Sync") — still open.
- Prompted graph refresh cadence: badge quietly + ask on next open (default),
  vs modal immediately.
- Tombstone horizon 90 days / stale-manifest cutoff 30 days (defaults) —
  any pair works while cutoff < horizon.
