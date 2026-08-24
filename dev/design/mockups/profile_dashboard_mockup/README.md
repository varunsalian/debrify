# Profile & Security Instrument — mockup

`index.html` — open directly in a browser. The viewport switcher (Phone / Tablet / Desktop / TV)
is document chrome, not part of the app.

## Why

Profiles landed as a ~40k-line change and the only visual representation of its state is
`ProfileDiagnosticsService.collectJson()` — a raw JSON blob dumped behind Manage Profiles and
Edit Profile. Isolation bugs are invisible until someone goes looking in code.

This screen inverts that: **every row declares who owns the data and whether it is bound to the
active profile right now.** A leak renders as a red row. An empty Faults panel is the pass condition.

The sample data deliberately shows two real faults found in the 2026-08-14 audit (stale
`EngineRegistry`, a plaintext credential) so the design can be judged on whether it actually
surfaces them.

## Panels and where the data comes from

| Panel | Source |
|---|---|
| Status ribbon | `ProfileRuntime.capture()`, `registry.privacySafeDiagnostics()` |
| Faults | computed — cross-checks the panels below against the active scope |
| Isolation matrix | `ProfileScope`, `ProfileStoragePaths`, `ProfileDatabaseSnapshot`, `NativeProfileProjection`, `job_ownership` |
| Process caches | the `ProfileAppLifecycleParticipant` participant list + each singleton's warmed scope |
| Credential vault | `SecretVault.isSealed()` per key, `vault_key_source_v1` |
| Transport & backup | `remote_static_keypair_v1`, `remote_paired_devices_v1`, backup envelope params, sanitized-export filter |
| Profiles | `registry.listProfiles(includeDisabled: true)` |
| Connections & grants | `ConnectionResourceService` + `registry.getGrant()` |
| Generations & storage | `profile_data_generations` + directory sizes |

Two panels need new plumbing:

- **Process caches** — singletons don't currently record which scope they were warmed for.
  `EngineRegistry` gained a `_loadedScopeKey` in `99e91da`; the same idea generalised to a small
  registry of participants is what makes this panel possible, and it is the only panel that can
  catch the leak class the storage layer can't see.
- **Sanitized export row** — counts how many profile keys pass the export filter, so the denylist
  can't silently drift.

## Responsive behaviour

The surface is a container query context (`.stage`), so it responds to the frame, not the window.

- `< 660px` — one column; every table row becomes a labelled stack via `data-label`, nothing
  scrolls sideways
- `660–1039px` — two columns, wide panels span both
- `≥ 1040px` — three columns
- TV — same grid, larger base size, generous hit targets

## Placement

Proposed: **Settings → Advanced → Profile & Security**, Admin-only, alongside the existing
diagnostics action rather than replacing it — "Export JSON" stays for bug reports.
