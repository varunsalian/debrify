# tvOS preference budget — crash-only fix

**Date:** 2026-08-14
**Branch:** `feature/profiles`
**Audit:** `docs/superpowers/reviews/2026-08-14-apple-tv-storage-memory-growth-audit.md`
**Scope:** stop the CFPreferences process termination from recurring. Nothing else.

## Problem

tvOS terminates the process when the `UserDefaults` database reaches 1 MiB
(`__CFPREFERENCES_HAS_DETECTED_THIS_APP_TRYING_TO_STORE_TOO_MUCH_DATA__`).
Four crash reports on the Bedroom Apple TV confirm this was the startup
failure. The trigger was profile migration duplicating a large rebuildable
TVMaze cache into a scoped namespace.

`c4a31b0a` removed that specific trigger by pruning TVMaze entries before
bootstrap and migration writes. What is still missing is a general rule that
*no* write may push the database toward the platform limit. Ordinary user data
(`playback_state_v1`, episode progress, `series_source_*`, playlists) is
unbounded, so the same termination can recur without TVMaze involved.

## Scope

**In:**

1. A pre-write budget that refuses growth before the native database can reach
   the platform limit.
2. A migration preflight so the budget can never abort migration midway.

**Deferred** (tracked in the audit, not attempted here): moving bulk stores to
SQLite; transactional recovery-envelope capacity; legacy-source cleanup;
disk-quota work; import bounding; artwork byte caps; XMLTV measurement; the
`sizeLimitExceededNotification` observer; native size probing.

## Key constraints discovered during investigation

**1. An uncaught exception during bootstrap is a startup crash.**
`lib/main.dart:224` catches only `ProfileBootstrapRecoveryRequired`. Every
other exception out of `ProfileBootstrap.initialize()` escapes `main()` and the
app does not start. So the guard must never throw on a write path, and
migration must decide up front rather than fail partway.

**2. Several bulk writers throw when a setter returns `false`.** Refusing their
writes would convert the CFPreferences kill into a Dart crash:

| Site | Path |
|---|---|
| `profile_migration_service.dart:720` | legacy migration copy |
| `profile_data_generation.dart:420` | generation staging / restore |
| `profile_registry.dart:485` | tvOS recovery rebuild |

The recovery rebuild at `profile_registry.dart:485` is the most dangerous: it
repopulates preferences from the Keychain envelope after a cache purge. A
refusal there would break profile recovery outright.

**3. But the recovery rebuild already bypasses the chokepoint.** It writes via
a raw `SharedPreferences.getInstance()`, not `ProfilePreferences`, so it never
reaches `_write()` and is exempt for free.

**4. Ordinary runtime writes never inspect the result.** All 144
`await prefs.setString(...)` call sites ignore the returned bool, so a refusal
there can only ever be a silent skip — never a throw.

These four facts determine the gating rule below.

## Design

### 1. `ProfilePreferenceBudget` (new, `lib/services/profiles/`)

Pure Dart. No native code, no method channel, no new plugin registration.

```
measure(SharedPreferences) -> int
```

Sum over every key of `utf8(key).length + valueBytes + perKeyOverheadBytes`,
where `perKeyOverheadBytes = 64` models binary-plist structure plus the
`flutter.` prefix the plugin adds natively (the app never calls `setPrefix`).
The result deliberately **overestimates** the on-disk size.

`valueBytes` must match on `List<Object?>`, **not** `List<String>`. The
`shared_preferences` in-memory cache stores string lists as `List<dynamic>`, so
the existing `_preferenceFootprint` in `profile_migration_service.dart` scores
them as 16 bytes. That is harmless where it is used today (ordering a
delete-everything loop) but would make a budget undercount a large list by
orders of magnitude. The existing helper is left untouched to keep the diff
minimal; the new module implements this correctly.

Why Dart-only is sound: `shared_preferences` keeps every value in an in-memory
Dart map, so a full measurement is a few hundred O(1) lookups — cheap enough to
run on every write, which removes cache-drift entirely. Everything that *grows*
is written from Dart, so Dart's view captures 100% of the growth. Native and
plugin keys are invisible but small and constant, and are covered many times
over by the margin below.

**Threshold:** a single limit of **384 KiB measured**. Platform kill is 1 MiB.

An earlier draft added a soft "prune first" tier below the limit. It was
dropped: `c4a31b0a` already disabled TVMaze persistence on tvOS and
`profile_bootstrap.dart:70` prunes at every launch, so a runtime prune would
find nothing. Dropping it also keeps admission synchronous and avoids a
circular import between the budget and the migration service. Migration needs
no prune tier either — the existing prune already runs immediately before the
preflight measures.

Byte counting is exact but allocation-free (a manual UTF-8 width loop rather
than `utf8.encode`, which would allocate a copy of every string on every
write). A full measurement at the limit is ~200k iterations, cheaper than the
platform-channel round trip it guards.

384 KiB is the audit's recommended ceiling. Because the measurement
overestimates, refusals begin near Apple's own 512 KiB *warning* line, not near
the kill line. Bedroom measured ~72 KiB, so a real install has ~5x headroom.

**Only-grow rule.** A write is always admitted when it does not increase the
total (`projected <= current`), even above the hard limit. Without this, an
over-budget install could never shrink itself back and would be permanently
stuck. This is a correctness requirement, not an optimisation.

**Platform gate.** Active only on tvOS, via an injectable `tvOs` override
mirroring `pruneTvOsTransientPreferenceCaches`. `PlatformUtil.isTvOS` is a
`static final` and cannot be overridden, so the parameter is how tests drive
it. Every other platform is byte-for-byte unchanged.

### 2. `ProfilePreferences._write()` admission — ordinary writes only

`profile_preferences.dart:165` is the single chokepoint for every scoped and
legacy write. Check admission before calling `operation()`.

**Gate only instances built by `ProfilePreferences.instance()`** — that is,
`_capturedAccess == null`. Every `forCapturedScope` instance (migration,
restore, profile creation, generation staging, native projection) is exempt.

This is the core safety decision, and it is what keeps the change regression-free:

- Ordinary runtime writes are the *only* source of the unbounded growth that
  causes the crash — playback state, episode progress, `series_source_*`,
  playlists all accumulate here. Gating them is sufficient.
- Ordinary writes are also the only writes whose result is never checked
  (constraint 4), so a refusal is always a silent skip.
- Every exempt bulk path is bounded by something else. Verified individually:

| Path | Reaches `_write()`? | Bound |
|---|---|---|
| Recovery rebuild (`profile_registry.dart:485`) | No — raw `SharedPreferences` | 512 KiB / 768 KiB envelope caps |
| Generation staging (`profile_data_generation.dart:288`) | No — raw `SharedPreferences` | source generation, itself capped |
| Legacy migration | Yes, `migration` | the preflight below |
| Restore coordinator | Yes, `restore` | portable-package limits |
| Profile creation | Yes, `profileCreation` | fixed 24-key scalar list (`copyablePreferenceKeys`) |

Profile creation was the one I expected to be a hole — a new profile copying
from a capped source could in principle double the database. It is not: the
copy list is 24 small scalar settings (theme, scale, languages), a few hundred
bytes.

On refusal **return `false` — never throw.** That is the existing failure
signature of `SharedPreferences`.

`remove()` and `clear()` shrink and are never gated.

`DevicePreferences` writes are counted in the measurement but not gated: that
allowlist is device infrastructure (download queues, pairing) where a silent
failure is worse than the bytes it saves.

### 3. Migration preflight

In `ProfileMigrationService.migrate()`, immediately after the existing TVMaze
prune and `_classifyKeys` and **before `createProfile`**, measure the current
total plus the footprint of every key to be copied. If it exceeds the hard
limit, prune and re-measure. If it still exceeds, **do not migrate.**

Running the preflight before `createProfile` means a refusal mutates nothing at
all — no staging profile, no journal entry beyond the preflight record.

Because migration writes are exempt from the guard, the preflight is the only
thing bounding them — and monotonicity is what makes it sufficient. The copy
loop only adds keys, so the total after the last copy is exactly what the
preflight projected; the install lands under the hard limit. Re-copying a key
left by an interrupted run adds nothing, so the preflight only ever
overestimates.

**Signalling.** `migrate()` returns `Future<UserProfile>`, so the failure is
raised as a dedicated `ProfilePreferenceBudgetExceeded` exception and caught at
the single tvOS call site, `profile_bootstrap.dart:236`. It is caught there and
never rethrown, so it cannot reach `main()`. The other `migrate()` caller
(`profile_bootstrap.dart:407`) is Linux-only and unreachable for a tvOS-gated
preflight; it is left alone.

`ProfileBootstrap` handles the caught failure the way it already handles a
locked device key at `profile_bootstrap.dart:228-234`: close the registry,
clear the callback, `ProfileRuntime.initializeLegacy()`, return. The app starts
normally in legacy mode and retries on a later launch. No crash, no data loss,
no partial migration.

## Files

| File | Change |
|---|---|
| `lib/services/profiles/profile_preference_budget.dart` | New. Measurement + admission. |
| `lib/services/profiles/profile_preferences.dart` | Admission in `_write()`. |
| `lib/services/profiles/profile_migration_service.dart` | Preflight before the copy loop. |
| `lib/services/profiles/profile_bootstrap.dart` | Degrade to legacy mode on preflight failure. |
| `test/profiles/profile_preference_budget_test.dart` | New. |
| `test/profiles/profile_preferences_test.dart` | Extend. |
| `test/profiles/profile_migration_service_test.dart` | Extend. |

## Tests

1. Measurement counts keys, values, and per-key overhead; list values sum
   elements.
2. Under budget on tvOS: writes behave exactly as today.
3. Over budget on tvOS: a net-growth write returns `false` and does not throw.
4. Over budget on tvOS: a shrinking or equal write is still admitted.
5. `remove`/`clear` always work above the hard limit.
6. Non-tvOS: identical behaviour above and below every threshold.
7. Migration preflight passes for a normal key set and copies everything.
8. Migration preflight fails for an oversized key set, throws nothing, and
   leaves the install unmigrated and usable.
9. Prune tier reclaims TVMaze space and lets a write through that would
   otherwise be refused.
10. Full suite (214 files) plus `flutter analyze` for regressions.

## Risks

| Risk | Mitigation |
|---|---|
| Silent data loss in the 384 KiB–1 MiB window where the app works today | Accepted: that window is on the way to a guaranteed unbootable app. A dropped playback position beats an app that will not launch. Logged for diagnosis. |
| Threshold calibrated from one device | Conservative measurement plus ~5x headroom over the only real observation. Native validation is a documented follow-up. |
| Guard aborts migration | Removed by design — preflight decides before any write, and failure degrades to legacy mode. |
| Behaviour change off tvOS | Platform-gated; tests assert non-tvOS parity explicitly. |
| Credential write refused near the ceiling | Rare, and only in an already-broken state. Noted as a follow-up rather than special-cased, since exemptions weaken the guarantee. |
| Generation staging still duplicates a profile's preferences | Deferred, and safe as a consequence of the guard: capping the steady state at 384 KiB means even a full duplication lands near ~800 KiB, still under the 1 MiB kill. Today, with no cap, that same doubling is unbounded — so this is strictly improved, not merely unchanged. |

### Implementation notes that are correctness requirements

- Measure via `_delegate.getKeys()`, never `ProfilePreferences.getKeys()` — the
  latter is filtered to the captured scope, and the platform limit is
  database-wide.
- `_write()` already evaluates `PlatformUtil.isTvOS` (via
  `TvOsProfileRecoveryStore.supported`) on every platform including web, so
  adding a second tvOS check introduces no new platform risk.

## Rollback

Four contained changes behind a tvOS gate. Reverting the commit restores
current behaviour exactly; no schema, no migration, no persisted state.

## Outcome

Implemented as planned. 13 new tests across three files; all 286 profile tests
pass.

Regression evidence: the full suite's failing-test set was captured before and
after the change and is byte-identical — 9 pre-existing failures in
`test/series_parser_test.dart` (title parsing, unrelated), none introduced and
none fixed. `flutter analyze` reports the same 1966 repo-wide issues before and
after, with zero in any changed file.

Coverage check: `ProfilePreferences.instance()` is used at 555 call sites
including every `StorageService` accessor, against 33 raw
`SharedPreferences.getInstance()` uses — all of which are infrastructure
(remote pairing, device keys, native projection) or already-bounded paths
(recovery import/export, generation staging). Every unbounded store named in
the audit is behind the gated chokepoint.

Two additions beyond the plan, both small: a one-shot `debugPrint` on first
refusal (byte counts only — key names and values carry titles and identifiers),
and an explicit note that admission is synchronous while the write it guards is
awaited, so two writes racing at the boundary can overshoot by one value. The
~640 KiB gap between the limit and the platform threshold absorbs that.

### Defects found in review and fixed

A `/code-review high` pass over the working tree found two real defects in the
first implementation:

1. **The preflight and the runtime guard shared one ceiling.** Because
   migration is non-destructive, an install whose legacy keys measured ~190 KiB
   projected to ~380 KiB, passed a 384 KiB preflight, and landed permanently
   saturated — migrating successfully into a state where every subsequent write
   is refused. Fixed with `migrationReserveBytes` (128 KiB): the preflight now
   projects against `migrationLimitBytes` (256 KiB), so a migration only
   proceeds if it leaves room to keep working afterwards.

2. **Refusals would have silently dropped credentials.**
   `SecretVault.setString` returns `Future<void>` and discards the write
   result, and sealing makes a value larger than its plaintext — so on a
   saturated install the UI would report a saved API key that was never
   written. The plan had noted this as an accepted follow-up; that was too
   generous. Fixed with a small-write reserve: above `limitBytes` only writes
   of `smallWriteBytes` (4 KiB) or more are refused, and everything stops at
   `emergencyLimitBytes` (512 KiB) — Apple's warning line, still far below the
   1 MiB kill.

Also corrected: the bootstrap refusal now logs (it precedes the migration
journal's first entry, so it was previously undiagnosable); the class doc
claimed measurement was "a few hundred O(1) lookups" when it is O(total stored
bytes); the "a refusal mutates nothing" comment ignored the TVMaze prune that
runs just before it; and the Linux `migrate()` call site now documents why it
needs no handler.

### Known and accepted

`DevicePreferences` and the direct `SharedPreferences.getInstance()` writers
(remote pairing, desktop schedules) are counted by `measure()` but never
refused. That is deliberate — they are device infrastructure where a silent
failure is worse than the bytes — and it leaves a residual path: device-scoped
keys alone could in principle climb toward the platform limit. Their contents
are human-scale (pairing records, dismissed campaign IDs, a config cache), so
this is documented rather than gated.

Deliberately not done, and still open: no native size probe, so the threshold
is calibrated from one device; no `sizeLimitExceededNotification` observer; the
bulk stores are capped rather than moved to SQLite, which remains the real fix.
