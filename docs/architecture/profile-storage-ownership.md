# Profile storage ownership

This manifest is the compatibility contract for the profiles rollout. Unless a
key or path is explicitly device/job-owned below, existing Debrify state is
profile-owned and migrates to the initial Admin.

## Preference ownership

| Owner | Keys / prefixes | Notes |
|---|---|---|
| Device | `profiles_*_v1`, `app_onboarding_complete_v1`, `vault_key_source_v1` | Bootstrap authority mirrors and device-key continuity only. |
| Device remote identity | static keypair, paired devices, known receivers, receiver name/discovery/listen state | Pairing identifies an installation. Per-profile command permission is not stored here. |
| Device pending actions | `pending-external-actions-v1.json` | Bounded, device-key sealed, 24-hour launch/share queue; consumed before dispatch after local profile unlock. |
| Device jobs | download pending/paused/history, Android recording engine/concurrency, desktop schedules, recording history | Execution continues when its owner is inactive or PIN-locked. Every durable record must gain owner/revision fields. |
| Device platform | approved executable catalog, writable destination grants, battery/setup notices, OS capability probes | A profile stores only its selected reference. |
| Profile | all remaining `StorageService` keys | Includes presentation, navigation, playback, provider selection, Home, IPTV, Debrify TV, integrations, content policy preferences, and history. |
| Profile dynamic | `engine_*`, `series_source_*`, `discover_sort_*`, subtitle keys, Stremio addon JSON, `tvmaze_cache_*`, `tvmaze_timestamp_*` | Accessed only through `ProfilePreferences`. |
| Resource | provider/tracker/WebDAV/IPTV/addon/indexer credentials and shareable connection configuration | Converted from legacy preference/vault keys into sealed resource payloads; never copied by profile-copy UI. |
| Profile migration | essential-addon seeding state | Version markers are device-wide; seeding markers are profile-owned. |

`ProfilePreferences` uses `p.<opaqueProfileId>.g.<generation>.<logicalKey>`.
Legacy mode remains byte-compatible with unprefixed keys. A committed migration
retains those unprefixed keys read-only for the rollback window.

## Files and databases

| State | Owner | Location rule |
|---|---|---|
| `profiles.db` | Device registry | Durable application-support storage except tvOS, where it is a purgeable projection reconstructed from the recovery store. |
| `debrify_tv.db` | Profile | Profile generation directory; tvOS treats it as reconstructible activity/cache. |
| `iptv_catalog.db` | Profile | Profile generation directory; credential-bearing rows must be normalized or sealed. |
| imported engine YAML/config | Profile | Profile generation documents directory. |
| private EPG data | Profile/resource | Profile generation cache/support directory; public account-independent guide data may use global cache. |
| custom subtitle font files | Device asset | Selection is profile-owned; imported file and access grant are device-owned. |
| downloaded and recorded media | Device/public artifact | Never silently moved or deleted; visibility comes from owner metadata. |
| download/recording/schedule stores | Device job | Backend remains execution authority and reconciles with `job_ownership`. |
| Top Shelf/App Group snapshot | Device projection | Contains a revisioned, privacy-safe snapshot for the active unlocked owner only. |

## Startup boundary

Before `ProfileBootstrap`: Flutter/platform bindings, desktop/SQLite platform
initialization, primary-instance acquisition, and device-key/recovery access.
After scope publication: `SecretVault` legacy work, `StorageService` warms,
theme/layout/player settings, Discover, startup IPTV, Top Shelf ownership,
playback cleanup, schedules, recording coordinator, and catalog prewarm.

Direct preference opens are source-guarded. Reviewed exceptions are device-key,
remote-pairing, device-job, and platform-notice stores.

## Process and asynchronous ownership

Trakt, Simkl, PikPak, MDBList, M3U, Xtream, Stremio, Discover, subtitle,
engine, theme, and profile database state is cleared or rewarmed at every
activation boundary. Provider tokens are not retained in the PikPak singleton.
OAuth/PIN attempts and token refreshes capture the initiating profile scope and
authorization revision; successful completion revalidates that capability and
writes only through its captured generation. Provider logs are source-guarded
against URLs, credentials, response bodies, identifiers, and raw exceptions.

## Connection lifecycle

A borrower disconnect is privilege reduction: all of that profile's bindings
to the resource and its grant are removed atomically, without changing the
owner's sealed secret or revoking the upstream account. An owner may delete an
unshared resource only when it has no active jobs. Shared owner disconnects
fail closed until an Admin explicitly revokes borrowers or transfers ownership;
ownership transfer re-seals the secret with the new owner-bound associated data.
Only a successfully deleted unshared owner connection may trigger upstream
token revocation.
