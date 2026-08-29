# Profile backup coverage

This is the compatibility contract for encrypted profile backups and the
Remote **Include all profiles** transfer. A newly added profile preference,
resource field, or durable profile file is covered automatically only where
the rules below say so; new execution-bearing paths or new file families must
be reviewed here and in the matching codec.

## Package modes

| Mode | Restored coverage | Deliberate merge behavior |
|---|---|---|
| Single profile | Every portable scoped preference, both profile databases, engine YAML/YML/JSON, the current custom avatar attachment, and every owned active or disabled connection with its secret, binding, permission, and local settings. | Restores into a shadow generation of the signed-in profile. Its setup/lock settings are applied, but its name, avatar selection, role, policy, PIN, and enabled state remain the destination's. Borrowed connections are owned by another profile and cannot travel alone. |
| All-profile graph | Every active or disabled profile, name/avatar/role/policy/setup state, PIN and recovery verifiers, lock settings, scoped data, and the complete active-or-disabled resource graph: owners, secrets, grants, bindings, permissions, and per-profile resource settings. | Imported profile and resource IDs are remapped and published atomically beside the existing recovery Admin. Authorization revisions, timestamps, and staging history are regenerated locally. |
| Sanitized settings | The small, explicit `SanitizedProfilePreferences` appearance/player allowlist only; no identity, resources, database, history, or files. | Intended for unencrypted sharing, not complete recovery. |

All sensitive file packages require passphrase encryption. Remote graphs use
the same all-profile exporter and restore coordinator inside the paired,
authenticated encrypted session. New comprehensive exports use package v4 so
older v3 readers fail instead of silently ignoring disabled/lock state; v3
plain-sanitized and encrypted packages remain import-compatible. Import keeps
the decoded source version: v3 preferences newly classified as cache,
superseded resource authority, or device execution state are ignored exactly
as a v4 exporter would omit them, while an unexpected forbidden key in a v4
package remains a hard failure.

## Scoped preferences

The comprehensive exporter enumerates every stored key under the profile's
current generation; it is not a list of known UI settings. Boolean, integer,
double, string, null-removal, and string-list values are retained unless the
shared export/import policy below rejects or transforms them.

Safe platform-specific settings remain portable. Android/tvOS renderer and
audio modes, iOS/Linux/Windows built-in player choices, keyboard, navigation,
layout, theme, subtitle, and player controls are passive values: unsupported
platforms ignore them or their readers normalize them. A platform name alone
is not a reason to discard a setting.

| Rule | Exact coverage |
|---|---|
| Included by default | All remaining `StorageService`, engine, Discover, Home, playlist, favorites, watchlist, search/history, filtering, tracking, IPTV, Debrify TV, Stremio TV, subtitle, renderer, audio, layout, theme, navigation, startup, and playback preferences. User playlist/stream/addon/catalog URLs remain because they are requested content inside an encrypted package. |
| Resource authority excluded | Any key matching `api.?key`, `password`, `access.?token`, `refresh.?token`, `credential`, or `secret`; plus `real_debrid_api_key`, `torbox_api_key`, `premiumize_api_key`, `alldebrid_api_key`, `mdblist_api_key`, `mdblist_username`, Reddit/Trakt/Simkl token and username fields, `trakt_token_expiry`, all PikPak email/password/token/device/captcha/user fields, and WebDAV base URL/username/password. The encrypted resource graph is the sole portable authority for these. Dynamic `engine_*` settings with credential-shaped IDs are the one exception, and only in a secret-inclusive encrypted/authenticated package: custom engine settings have no registry-resource representation. |
| Legacy resource collections excluded | `webdav_servers_v1`, `indexer_manager_configs_v1`, `iptv_playlists`, and `stremio_addons_v1`. Their normalized connection resources travel instead, including file-imported M3U content. `real_debrid_endpoint` is operational endpoint state and does not travel. |
| Device/runtime state excluded | Every `remote_*` key, `initial_setup_complete_v1` (the authenticated profile record supplies setup state), battery-optimization status, download tree URI/name/path, and the custom-font registry. |
| Executable capabilities excluded | Custom executable paths/names/commands and iOS custom URL-scheme templates. A custom player selection is removed with its missing capability; built-in player selections remain. A selected custom subtitle-font ID is removed with the device-owned font file, while built-in font IDs remain. |
| Series source transformed | `series_source_*` keeps cloud/addon sources and removes local-service entries plus `localPath`, `localUri`, `localKind`, `localSizeBytes`, `localModifiedAt`, and `filePath`. A malformed or local-only binding explicitly clears during restore. |
| Playback transformed | `playback_state_v1` keeps title/identity, position, duration, speed, aspect, timestamps, and completion. It recursively removes `url`, `videoUrl`, `streamUrl`, local path/URI fields, and request headers so a restored profile cannot reuse a local path or expired/credential-bearing resolved stream. |
| IPTV execution state cleared | `iptv_last_live_channel` and `startup_iptv_channel` are source-device-vault ciphertext whose resolved stream URL can embed an Xtream password. They explicitly clear during restore; startup enablement and mode still travel, so the destination resolves from its own restored playlists instead of executing a source-device URL or headers. |
| Response caches excluded | `tvmaze_cache_*` and `tvmaze_timestamp_*`. Stable TVMaze mappings remain. |

The same policy runs again during import. A crafted package cannot bypass an
export-side rejection, and malformed transformed state clears or fails closed.
Exact resource IDs are rewritten in scalar strings, string lists, JSON map
keys/values, resource secrets, and per-profile resource settings.

## Registry and connection graph

All-profile backup covers every connection type: Real-Debrid, TorBox,
Premiumize, PikPak, AllDebrid, WebDAV, Trakt, Simkl, MDBList, Reddit, M3U,
Xtream, XMLTV, Stremio addons, Jackett, and Prowlarr. Disabled profiles and
disabled resources stay disabled after restore. Grant permission masks are
re-applied through the destination role ceiling, so a Child cannot gain
manage/share/reveal privileges from a package.

PIN cleartext never exists. The all-profile graph carries only a bounded
Argon2id hash/salt/parameter record and optional recovery verifier inside the
encrypted/authenticated package. It omits failed-attempt counters and lockout
timestamps. A missing or malformed carried verifier produces an Admin-reset-
required profile instead of an unprotected one.

The registry deliberately does not carry device authority or recovery
internals: active-profile selection, authorization/activation revisions,
registry generations, migration and restore journals, device-state rows,
resource secret chunk layout, job ownership, owned-artifact ledgers, or the
device encryption key. Destination IDs, revisions, timestamps, sealed resource
envelopes, generations, and journals are newly created.

## Databases and files

Both known profile databases are exported as consistent, integrity-checked
SQLite images. The normal file backup includes every table, including Debrify
TV's complete saved hash pools. If size requires compaction—or Remote
explicitly retries compacted—Debrify TV is omitted as one coherent feature
rather than restoring unusable channel shells. The user must confirm this
before the compacted package is saved or sent and is directed to the dedicated
Debrify TV **Export** action. That action creates a selected-channel ZIP (all
channels selected by default) with one YAML member per channel and the complete
saved pool. The existing **Import → From storage** flow restores the ZIP after
the profile restore. **Remote → Debrify TV Channels** remains the direct-device
convenience path.

| Database | Durable user state that remains | Tables omitted during compaction |
|---|---|---|
| `debrify_tv.db` | `iptv_lists`, `iptv_list_channels`, `iptv_watch_history`, `video_resume`, and any other non-Debrify-TV table | The complete Debrify TV feature: `tv_channels`, `tv_channel_keywords`, `tv_channel_cache_state`, `tv_cached_torrents`, `tv_keyword_stats` |
| `iptv_catalog.db` | `hidden_groups`, `channel_number_namespaces`, `channel_number_aliases`, `channel_number_assignments`, and any other non-cache table | `meta`, `catalogs`, `channels`, `epg_programmes`, `epg_guides` |

If the durable compacted images still exceed the package budget, export fails
visibly; it never silently drops a database. Restored resource IDs are also
rewritten in IPTV list/watch-history playlist references and channel-number
source aliases/namespaces.

Portable profile files are limited to engine `.yaml`, `.yml`, and `.json`
under `engines/`, plus the one image referenced by the current avatar key.
Symlinks, unknown paths, stale avatars, custom subtitle font files, executable
binaries, temporary restore files, SQLite sidecars, cache files, downloaded
media, and recorded media do not travel.

## Device-owned exclusions

The following are intentionally outside both file and Remote profile graphs
because restoring them would either claim authority the destination does not
have or start/rebind device work:

- every `DevicePreferences` value: profile bootstrap/projection state, active
  selection, remote identity/pairings/receiver name, update and support-cache
  state, donation/notice acknowledgements, recording concurrency/nudges,
  pending/paused download queues, legacy queue authority, custom-font registry,
  tvOS Top Shelf/profile-gate device choices, and native launch snapshots;
- device encryption/key-wrap material, filesystem/SAF grants, download
  destinations, imported font files, and custom executable/command/scheme
  capabilities;
- active or historical download, recording, schedule, retry, and queue jobs,
  their ownership/revision ledgers, and downloaded/recorded binaries;
- failed PIN attempts and current lockout time, process/runtime caches,
  migration/cleanup journals, old data generations, and remote peers/sessions.

## Remote **Include all profiles**

The toggle is offered only to an authorized Admin. A discovered receiver must
advertise comprehensive graph protocol v5; a manual-IP/VPN target remains
eligible until its authenticated handshake reports and cryptographically binds
the actual peer version. The sender uses
`exportAllProfiles(includeSecrets: true)`—not the older piecemeal configuration
builder—and chooses raw JSON or gzip in one worker-isolate pass. A graph above
the 32 MiB soft expansion threshold, above the 10 MiB wire budget, or above the
hard limit on its first pass is retried in compact mode. Compact mode keeps
durable IPTV/history rows but omits Debrify TV channels and pools together,
after explicit sender confirmation. Compacted JSON may expand to at most 48
MiB on the receiver, and a still-oversized graph fails visibly. The receiver
verifies authentication, package integrity, bounds, local Admin authority, and
user confirmation before the atomic graph restore, then reports the actual
import result to the sender.
