# Profile security and privacy model

Profiles isolate accidental access inside Debrify; they are not separate OS
users and do not defend against a device owner with filesystem/root/debugger
access. Public download and recording files may remain visible to other apps.

## Protected boundaries

- PINs are one-way Argon2id hashes with per-profile salts, persisted lockout,
  and constant-time verification. PIN digits are never logged or backed up.
  A comprehensive encrypted/authenticated profile-graph package can carry the
  bounded hash, salt, KDF parameters, and recovery-code verifier so an imported
  profile keeps its PIN; failed-attempt counters and lockout timestamps never
  travel. A reset-required profile carries no usable verifier.
- Resource secrets use versioned authenticated encryption bound to resource ID,
  type, owner profile, public schema, and secret-envelope version. Tampering,
  row swapping, and key loss fail closed.
- Policies, grants, bindings, routes, remote commands, external playback,
  downloads, recordings, backup, restore, and profile management authorize at
  the operation boundary—not only by hiding UI.
- Async work captures its owner scope and authorization revision. OAuth/PIN
  completions and provider refreshes revalidate before storing tokens, so a
  profile switch cannot redirect a result to the newly active profile.
- Pre-unlock links and secondary-instance arguments are size/count bounded,
  device-key sealed at rest, expire within 24 hours, and are consumed before
  dispatch so a crash cannot replay them into a later profile.
- Native/background jobs carry immutable owner/resource IDs and authorization
  revisions; PIN lock does not cancel already-authorized work.
- Locked notifications, Top Shelf, logs, analytics, errors, and backup previews
  omit URLs, headers, tokens, PIN input, and sensitive media metadata.

## Backups and transfer

Automatic OS backup/device transfer excludes registries, device-bound keys,
native job stores, profile generations, App Group projections, and retained
legacy secrets. Debrify comprehensive portable backups are passphrase-
encrypted, and Remote profile graphs ride an authenticated encrypted session.
If a carried PIN verifier is absent or malformed, the imported protected
profile requires Admin PIN reassignment before entry. Single-profile merge
restore never replaces the destination profile's PIN or identity policy.

Legacy v1/v2 backup and remote payloads import through a compatibility adapter
into a staging generation. Visibility changes only after validation and a
journaled registry publication; partial data is never exposed as current.

## Explicit non-claims

Debrify does not claim protection from rooted/jailbroken hosts, malicious OS
administrators, memory inspection in an unlocked process, compromised provider
accounts, or media copied outside the app. Desktop secret-store fallbacks and
the current legacy device-identifier vault are weaker than hardware keystores;
legacy decoding exists only for migration and is not the resource encryption
authority.
