# Dev-only profile audit tooling

Temporary. Built to find profile-isolation defects during development and to be
removed once that work is done. Not localised, not in settings search, no
schema-stability promise.

Plan: `design/plans/PROFILE_AUDIT_EXPORT_PLAN.md`.
Mockup: `design/mockups/profile_dashboard_mockup/index.html`.

## What it is

- `profile_audit_report.dart` — collects a per-profile inventory: preference
  keys with **salted hashes instead of values**, resources with their secret
  **key names** (never values), stores, generations, cache scopes, and computed
  findings. Safe to paste to a reviewer.
- `../../screens/profiles/dev/profile_data_screen.dart` — renders that same
  structure, plus an on-demand **Reveal** for the active profile only.

Entry point: Manage profiles → the `{}` icon in the app bar. Behind the Admin
PIN ladder **and** behind a compile-time flag.

## The flag is OFF

`kProfileAudit` (`profile_audit_flag.dart`) is
`bool.fromEnvironment('DEBRIFY_PROFILE_AUDIT', defaultValue: false)`, so this
tooling does not ship. It was `true` for one day (2026-08-15) so local
`--release` tvOS builds carried it without remembering a define, and was flipped
back the same day once alpha became real: an alpha is a release to other people,
and CI passes no defines, so the default was the only thing standing between a
raw key/value browser and a tester's screen.

Because `kProfileAudit` is a compile-time const, a build without the opt-in has
neither the entry point nor the code behind it — the tree-shaker drops both.

Turn it on for a single build without editing the file:

```
flutter-tvos build tvos --release --dart-define=DEBRIFY_PROFILE_AUDIT=true
```

Two tests guard this, and both are needed because either alone would permit the
tooling to ship: one pins that the entry point stays behind the flag (whichever
way the default points), the other pins that the default is off.

Deliberately not `kDebugMode`: the device this exists for is an Apple TV, and
tvOS builds are `--release`. A debug-only gate would hide the tool on exactly
the hardware it was written to debug.

## Removal recipe

1. `rm -r lib/services/profiles/dev lib/screens/profiles/dev`
2. `rm test/profiles/profile_audit_report_test.dart
      test/profiles/profile_data_screen_test.dart`
3. In `lib/screens/profiles/manage_profiles_screen.dart`: drop the
   `dev/profile_data_screen.dart` import, the `Profile data` `IconButton`, and
   `_openProfileData`.
4. In `lib/services/profiles/profile_preferences.dart`: drop
   `CapturedProfilePreferenceAccess.diagnosticsReadOnly` and its entry in
   `_readOnlyAccess`.

**Keep `profile_cache_ledger.dart`**, its stamps in
`profile_app_lifecycle_participant.dart`, `EngineRegistry.loadedScopeKey`, and
`test/profiles/profile_cache_ledger_test.dart`. That is the one piece meant to
outlive this tooling: no singleton otherwise records which profile scope it was
warmed for, which is why the `EngineRegistry` leak stayed invisible for as long
as it did.

## Reading the caches section

It is **empty until the first profile switch**, and that is correct rather than
a gap. The ledger records transitions: `_warm` runs on switch, reset and
rollback, not at startup. Before any transition every cache was populated for
the only profile that has been active, so there is nothing for it to be stale
against. Switch once and the table fills.

## Invariants worth not breaking

- **The report never contains a value.** Pinned by sentinel searches in
  `profile_audit_report_test.dart`. Live values exist only on screen, behind
  Reveal, for the active profile.
- **Salt is per export.** Hashes compare within one file, never across two.
  A stable salt would be a rainbow-table target that outlives the file.
- **Sealed values are excluded from duplicate detection.** AES-GCM re-nonces,
  so two profiles holding the same secret never collide. The grant matrix in
  `resources[]` is the authoritative answer to "do these share an account".
- **`secretKeys` only for resources the active profile is granted.** Listing
  keys for others would mean bypassing the grant model for a dev convenience.
