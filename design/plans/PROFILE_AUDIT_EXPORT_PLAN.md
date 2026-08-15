# Profile audit export + data browser — plan

**Dev-only. Temporary.** Built to find profile-isolation defects during
development and to be deleted afterwards. Not localised, not in settings search,
no TV focus-pool tuning beyond "it can be driven with a remote".

Design driver: the IPTV empty-`url` bug (26adfc1e/3bdacb90) took two hours of
spinner → guard → on-screen stack trace → migration helper. A per-profile
key/value view would have shown that resource simply **missing its `url` key**
at a glance. So the export must carry **key presence**, not only value equality.

Mockup: `design/mockups/profile_dashboard_mockup/index.html`.

---

## Goals

1. Answer "what does each profile actually hold?" without reading code.
2. Make cross-profile leakage visible: same value in two profiles.
3. Make missing/extra keys visible: the shape of the IPTV bug.
4. Produce a file that can be pasted to a reviewer **without leaking secrets,
   titles, URLs or watch history**.

## Non-goals

- Editing values. Read-only, always.
- Shipping to users. There is no migration, no schema stability promise.
- Covering non-profile state (engines' YAML content, media files).

---

## Tier 0 — cache scope ledger (KEEP after the rest is deleted)

The only piece worth surviving. No singleton records which scope it was warmed
for, which is precisely why the `EngineRegistry` leak was invisible until read
line by line.

`lib/services/profiles/profile_cache_ledger.dart`

```dart
abstract final class ProfileCacheLedger {
  static final Map<String, String> _stamps = {};
  static void stamp(String name, String scopeKey);
  static Map<String, String> snapshot();
  static void debugReset();
}
```

`ProfileAppLifecycleParticipant._warm` stamps each group **as it warms it**, not
all at once at the end. That ordering is the diagnostic: if `_warm` throws
partway, everything after the throw still shows the previous scope, which is
exactly the state that produces a leak.

`EngineRegistry` already tracks a real `_loadedScopeKey`; it reports that rather
than a stamp, so at least one row is precise rather than declarative.

~40 lines including the stamps. Everything below can be deleted without touching
this.

---

## Tier 1 — the exporter (the actual deliverable)

`lib/services/profiles/dev/profile_audit_report.dart`

Everything else in this plan is a way to *look at* what this produces. If time
runs short, this alone is the feature.

### Reading another profile's preferences

Must **not** use a raw `SharedPreferences.getInstance()`:
`test/profiles/profile_source_guard_test.dart` pins the exact call count per
file, and adding one there is a security-relevant edit that should not be
casually made for a dev tool.

Instead add `CapturedProfilePreferenceAccess.diagnosticsReadOnly` and route
through `ProfilePreferences.forCapturedScope(scope, …)`, which already exists
for migration/restore/native-projection. Add the new value to
`_assertWritable`'s refusal list alongside `nativeProjectionReadOnly` so the
handle is provably read-only.

That gives per-profile `getKeys()` returning **logical** keys — exactly the
inventory needed — with no new bypass.

### Privacy model

| Field | Treatment |
|---|---|
| Value | **Never exported.** Replaced by `hash` = first 8 hex of SHA-256(salt + utf8(value)) |
| Salt | 32 random bytes per export, **never written to the file** |
| Cross-export diffs | **Structure only.** A fresh salt per export means hashes never match across two files. Key presence, types and findings diff cleanly — which is what a before/after repro actually needs — but value equality is a within-file property only. Anything else would mean a stable salt, i.e. a rainbow-table target that outlives the file. |
| Key name | Exported, except ids are collapsed (below) |
| Profile id | Pseudonymised `profile-1`, `profile-2`, stable within the file |
| Type / length | Exported (`str`/`int`/`bool`/`double`/`list`, byte length) |

The salt is the whole trick: within one file, identical values collide, so
"these two profiles hold the same value" is visible. Across files or against a
rainbow table the hashes are meaningless.

**Where hash-equality does NOT work, and why that is fine.**
`ProfilePreferences.getString` returns the *stored* value, so a sealed key
returns `enc1:` ciphertext. AES-GCM uses a fresh nonce per seal, so two profiles
holding the same secret produce **different** ciphertext and therefore different
hashes. Duplicate detection is silently useless there, so the report must not
imply otherwise:

- Sealed entries are reported with `"sealed": true` and are **excluded** from
  `duplicate-value-across-profiles`.
- The real question — "do two profiles share this account?" — is answered
  authoritatively by the **grant matrix** in `resources[]`, not by guessing from
  hashes. Grants are the mechanism; hashes would only ever be a proxy for them.

Under profiles, credentials live in connection resources anyway: every
credential key is in the migration's `_resourceKeys`, so it is converted to a
resource and **never copied into the profile namespace**. A credential-shaped
key found in a profile namespace is therefore itself the finding — see
`credential-residue` below.

**Key-name collapsing.** `series_source_tt0903747` names a title the user
watched. Any key matching a known id-bearing pattern collapses to
`series_source_<imdbId>` with a `count`, and the hash covers the collection
rather than each entry. Patterns: `series_source_*`, `engine_*_*`,
`iptv_hidden_categories_*`. Unknown keys are exported verbatim — a new
id-bearing key is a plan-review item, not a silent leak.

### Sections

```jsonc
{
  "schemaVersion": 1,
  "generatedBy": "debrify-profile-audit",
  "runtime": { "mode": "committed", "activeScope": "p.profile-1.g.3.e.12",
               "packageVersion": 3 },
  "registry": { /* privacySafeDiagnostics(), verbatim */ },
  "profiles": [ { "id": "profile-1", "role": "admin", "generation": 3,
                  "authorizationRevision": 7, "hasPin": true,
                  "lockOnResume": true, "inactivityTimeoutMinutes": 15,
                  "setupComplete": true, "enabled": true } ],
  "generations": [ { "profile": "profile-1", "generation": 2,
                     "state": "retired", "ageDays": 2 } ],
  "preferences": {
    "profile-1": [ { "key": "app_theme", "type": "str", "bytes": 8,
                     "hash": "3ac91f0b" } ]
  },
  "devicePreferences": [ { "key": "remote_control_enabled", "type": "bool",
                           "hash": "…", "registered": true } ],
  "resources": [ { "id": "resource-1", "type": "iptvXtream",
                   "owner": "profile-1", "grants": {"profile-2": 3},
                   "secretKeysReadable": true,
                   "secretKeys": ["name","serverUrl","username","password"] } ],
  "stores": [ { "profile": "profile-1", "name": "debrify_tv.db",
                "health": "ok", "tables": {"video_resume": 214} } ],
  // health: ok | unhealthy | unavailable | absent. A non-active profile's DB is
  // opened directly read-only rather than through DebrifyTvDatabase, whose scope
  // machinery would (correctly) refuse a foreign scope. 16a8392d showed a
  // WAL-header database can fail SQLITE_CANTOPEN read-only when its -wal/-shm
  // companions are missing, so any open failure lands in "unavailable" and the
  // export continues — a diagnostic must never be the thing that throws.
  "caches": [ { "name": "EngineRegistry", "warmedFor": "p.profile-2.g.2",
                "matchesActive": false } ],
  "findings": [ { "id": "cache-scope-stale", "severity": "high",
                  "detail": "EngineRegistry warmed for another scope" } ]
}
```

`resources[].secretKeys` is the field that would have caught the IPTV bug
immediately: **key names only, no values** — a resource with no `url` is
visible at a glance.

**It is only populated for resources the ACTIVE profile is granted**, read
through the fully authorized `resolveSecretForUse`. Listing keys for a resource
the active profile cannot use would mean calling the private, unauthorized
`_openSecret` — a real hole in the grant model, opened for a dev convenience.
Not worth it, and unnecessary in practice: the developer runs as the Admin who
owns the resources. Everything else (`type`, `owner`, `grants`) comes from the
registry and is available for every resource, so an ungranted resource is still
*visible*, just not introspected. `secretKeysReadable: false` records which case
a row is, so an empty `secretKeys` is never mistaken for "no keys".

### Self-checks (`findings`)

The exporter runs its own assertions so a reviewer audits both the results and
the assertions:

- `cache-scope-stale` — a ledger entry whose scope ≠ active scope
- `device-pref-unregistered` — a key outside `DevicePreferences.allowedKeys`
- `credential-residue` — a credential-shaped key sitting in a **profile
  namespace**. Migration converts every such key to a resource, so on a migrated
  install this list should be empty; anything in it either escaped conversion or
  was written back afterwards. (This replaces a planned "credential-plaintext"
  check, which would have inspected the wrong store.)
- `resource-missing-required-key` — a granted resource whose secret is missing a
  key its model casts non-null. **This is the IPTV-bug detector.** Required-key
  table, taken from each model's `fromJson`:
  | Type | Required |
  |---|---|
  | `iptvM3u`, `iptvXtream` | `name`, `url`, `addedAt` |
  | `stremioAddon` | `id`, `name`, `manifest_url`, `base_url` |
  | `webDav` | (none — `fromJson` coalesces every field) |
  | `jackett`, `prowlarr` | (none — same) |
- ~~`duplicate-value-across-profiles`~~ — **not built as a finding.** The
  compare view's "Same value in both" bucket does this interactively and
  better: a static finding would have to either flood the list with meaningless
  matches (`app_theme`) or guess which ones matter. Unsealed values only either
  way, since AES-GCM re-nonces.
- ~~`device-pref-unregistered`~~ — **not buildable without a new bypass.** The
  export iterates `DevicePreferences.allowedKeys`, so an unregistered key is
  invisible to it by construction; finding one means scanning raw preferences,
  which is exactly the guard-pinned call the design avoids. The allowlist's own
  `_assertAllowed` already throws at write time, which is the better place.
**Deferred, deliberately:** `job-owner-unknown` (a `job_ownership` row naming a
profile that no longer exists). It needs a new per-owner query on
`profile_registry.dart` — a 4000-line, security-relevant file outside the
deletable `dev/` directory, which is the wrong trade for a throwaway tool. The
`registry` section already carries `jobs.ownerless` from
`privacySafeDiagnostics`, which is the same smell at lower resolution.

### Delivery

`ManageProfilesScreen` — already Admin-gated behind the PIN ladder, already
hosts `_showDiagnostics`. Add one row: **Profile data**. Two actions inside:
copy the JSON to the clipboard, or write it next to the existing diagnostics
export.

---

## Tier 2 — minimal viewer

Same screen, renders the report already in memory. Profile tabs (+ a Device
tab), grouped key list, type and seal badges. No search, no compare. Read-only.

Values shown as `hash` by default; a **Reveal** toggle reads the live value for
the *active* profile only (other profiles are never opened for their values,
only their key inventory). That keeps the "browse my own data" case useful
without turning the screen into a cross-profile secret viewer.

## Tier 3 — search + compare

- Filter box over key and value-preview.
- Compare two profiles, bucketed: **same hash** (amber), **differs**,
  **only in one**. The amber bucket is the isolation-bug smell; the third
  bucket is the IPTV-bug smell.
- Responsive: container queries; at phone width rows become labelled stacks.

---

## As built — deviations from this plan

All three tiers landed. Four things changed during implementation:

1. **Generations are read from the filesystem, not the registry.** There is no
   public per-profile generation query, and adding one meant editing a
   4000-line security-relevant file for a throwaway tool. Walking
   `profiles/<id>/g/` is also strictly more informative: it reports what
   storage actually holds, so a directory the registry forgot still appears as
   `retired-or-orphaned`.
2. **`_readDevicePreference` probes types.** `DevicePreferences` exposes typed
   getters only, and `getString` on a bool *throws*. The first draft chained
   `??` across them, which would have crashed on the first non-String key —
   `remote_control_enabled` on any real device. Caught in the Tier 1 review.
3. **The viewer takes a `debugCollect` seam.** `collect` does real file IO,
   which never completes under the widget tester's fake clock; widget tests
   inject a fixture collected inside `tester.runAsync` and the unit test covers
   collection with real IO.
4. **Reveal is implemented as planned but fetches separately.** Values are read
   live from `ProfilePreferences.instance()` for the active profile only —
   they are never put into the report structure, so the artifact stays safe to
   paste even though the screen can show real data.

18 tests: 5 ledger, 8 report, 5 screen. Full suite +3203/−9 (the 9 are the
documented pre-existing baseline).

## Constraints `profile_source_guard_test.dart` imposes

Checked before writing a line, because each would fail the build late:

1. **Raw `SharedPreferences.getInstance()` counts are pinned per file.** The
   exporter must go through `ProfilePreferences.forCapturedScope`; a raw call
   means editing a security allowlist for a dev tool.
2. **`'debrify_tv.db'` / `'iptv_catalog.db'` literals are confined** to six
   reviewed files. Use `ProfileDatabaseSnapshot.databaseNames`, which
   `ProfileDiagnosticsService` already does.
3. **`print(` is banned anywhere under `lib/services/`** (recursive, so `dev/`
   is covered) — `debugPrint` only. The regex is `\bprint\s*\(`, which
   `debugPrint` does not match.

## Deletion story

- All new code in `lib/services/profiles/dev/` + `lib/screens/profiles/dev/`,
  except Tier 0 (`profile_cache_ledger.dart`) and the enum value.
- One entry point (one row in `ManageProfilesScreen`).
- Removal = delete two directories, delete one row, drop the enum value and its
  `_assertWritable` line, unstamp `_warm`.

## Tests

- Hash: same value → same hash; different salt → different hash across runs.
- No raw value, no unpseudonymised profile id, and no id-bearing key appears in
  the encoded report (string search over the output, like the sanitized-export
  test).
- Key collapsing: 40 `series_source_*` keys → one pattern row with `count: 40`.
- Findings fire: a stale ledger stamp produces `cache-scope-stale`; a resource
  missing a required key produces `resource-missing-required-key`.
- Source guard: raw `SharedPreferences.getInstance()` count unchanged.

## Risks

1. **The report itself leaking.** Mitigated by hashing, pseudonyms and key
   collapsing, and pinned by a test that greps the output for sentinels.
2. **Scope-crossing while reading.** Reading N profiles means N captured scopes
   while one is active. All reads go through `forCapturedScope`, which is the
   mechanism migration/restore already use; no writes anywhere.
3. **tvOS preference budget.** `c4a31b0a` showed CFPreferences aborts the
   process when UserDefaults grows too large. The exporter only *reads*, and
   writes its output to a file/clipboard, never back into preferences.
4. **Cost on a large install.** 3 profiles × ~430 keys is fine; the DB table
   counts are `COUNT(*)` per table and run once per export, off the build path.
