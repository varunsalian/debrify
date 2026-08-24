# Profiles redesign — gate, settings hub, edit screen

Mock: `design/mockups/profiles_mockup/index.html`

Three surfaces change: the **gate** (first screen), a new top-level **Settings →
Profiles** hub, and a categorized **Add/Edit profile**. Underneath all three is
one new capability: avatars that can be images and GIFs.

Sequenced so each phase is shippable on its own. Phases 1–2 are foundation with
no visible change; 3 and 4 are the wins that don't depend on the gate concept;
the gate itself lands last, when the avatar system it shows off already works.

---

## Phase 0 — Decisions

**Gate concept.** Recommend **A · Portrait Wall**: the most room for imagery,
which is the point of the whole exercise, and it reads as the same room as the
shipped Spotlight home. Spotlight Stage and Halo Row are ~1 day variants on the
same widgets if you'd rather; only Phase 5 changes.

**Rollout.** Follow the house `*_style` pattern: a `profile_gate_style` pref
(`classic` | `wall`) defaulting to `classic` until the gate is device-tested,
then flip the default. Phases 3–4 ship unflagged — they're straight
replacements with no visual risk to the first screen.

**Not in scope.** The `ProfileFeature` policy editor stays off
(`EditProfileScreen._showFeaturePolicyControls = false`). Role remains the
feature-level control. If that editor is revived it slots back under Role.

---

## Phase 1 — Avatar model and storage

No UI. Everything below is invisible until Phase 2.

**Encode the source in the existing `avatarKey` string.** Do not add a field.
`avatarKey` is already `String?` on `UserProfile` and already crosses the wire in
`profile_package_service.dart` (2 sites) and `profile_restore_coordinator.dart`.
Keeping it a string means **zero package-schema change and no migration**:

| Value | Meaning |
|---|---|
| `person`, `child`, `movie`, `rocket`, `sports`, `music` | today's icons — still valid, unchanged |
| `art:aurora` | built-in art (see tiering below) |
| `file:avatars/<uuid>.gif` | user image or GIF |

Old builds reading a new `file:` key fall through the existing `switch` default
and render the role's default icon — degradation, not breakage.

- New `ProfileAvatar` value type (parse/format/`isAnimated`).

### Art tiering — draw it, don't ship it

*Phase 1 owns only the `art:<id>` key grammar; the painters and the id → painter
registry are Phase 2, since Tier 1 has no storage to model.*

The art avatars in the mock are gradients and keyframes, not photographs. Their
Flutter equivalent is a gradient plus an `AnimatedBuilder`, so the default set
should be **drawn in code**:

- **Tier 1 — procedural art (the default set).** A few KB of code for the whole
  library. No asset bytes, no network, nothing to purge, resolution-independent,
  and it animates only on focus like every other avatar. Its `dominantColor` is a
  compile-time constant, so nothing is computed or fetched at render.
- **Tier 2 — a small bundled illustrated set**, only if you want characters or
  mascots, which procedural drawing cannot do. Measure the APK delta before
  committing; a dozen tight WebPs is a few hundred KB, and the APK is already an
  open concern.
- **Tier 3 — a remote catalog. Deferred, not planned.** A GitLab
  `manifest.json` + raw files repo was considered and rejected for now: its best
  argument was purge-durability on tvOS, and bundled or procedural art beats a
  remote catalog on exactly that axis — catalog images would cache into the same
  purgeable directory. What remains (APK size, shipping art without a release)
  does not yet outweigh a new repo, moderation, manifest versioning, cache and
  staleness handling, and an IP leak to GitLab on the first screen.

**Keep the reversal free.** `art:<id>` is a namespace, not a storage location.
The resolver checks procedural first, then bundled; a catalog can be added later
as one more lookup behind the same key form — no data-model change, no migration,
no reissued keys. Revisit if the library grows past what is comfortable to ship.

**Avatars must live OUTSIDE the data generation.** Store at
`profiles/<id>/avatars/<uuid>.<ext>` — the profile root, a sibling of `g/<n>/`,
**not** `scope.fileIn(...)`.

`ProfileScope.generationDirectory` is `profiles/<id>/g/<generation>/`, and three
services publish a new generation: `profile_restore_coordinator`,
`profile_reset_service`, and **`profile_engine_assignment_service`**. That last
one is a routine Phase 3 action — an Admin changing which engines a profile gets.
Since `avatar_key` lives on the *profile row* and is not generation-scoped, an
in-generation file would be orphaned in the old generation by an unrelated engine
edit, and the avatar would silently revert to the role icon. Profile-root storage
keeps the file's lifetime matched to the key that points at it.

Deletion is already handled: `ProfileDataGenerationManager.deleteAllProfileData`
removes the whole `profiles/<id>` tree across the documents, support and cache
roots, so avatars go with it — and it already runs inside the
`ProfileCleanupLedger` schedule/complete pair, so a crash mid-delete converges.
What must *not* reach avatars is **generation** deletion, which is the point of
storing them at the profile root. Pin that coupling with a test rather than
assuming it: a future refactor narrowing `deleteAllProfileData` to generations
would start leaking avatar files.

The one lifecycle case still needing explicit work is **replacement** — picking a
new avatar has to delete the previous file, or the directory grows forever.

**Validate `avatarKey` before it ever resolves to a path.** Today it is written
raw — `profile_restore_coordinator.dart:125` reads `record['avatarKey'] as
String?` from an untrusted package and `profile_registry` stores it verbatim.
That is harmless while unknown keys just fall through the icon `switch`, but the
moment `file:` keys become paths, a crafted package carrying
`file:../../../<something>` is a traversal. Required in `ProfileAvatar.parse`
*and* at restore: allowlist the charset, reject separators and `..`, then
resolve and assert the final path is inside that profile's avatars directory.

**Reuse `ProfilePortableFiles`' codec, not its paths.** The base64 + sha256 +
size validation (4 MiB/file, 64 MiB total) is exactly right and should be shared.
Its path handling is not: `restore()` writes through `scope.fileIn(root,
'documents', ...)`, which is generation-scoped. Extract the codec, give it a
destination-resolver parameter, and let engines keep generation paths while
avatars use the profile root.

Also fix, while in there: `export()` early-returns
`if (!await engines.exists()) return {}`, so a profile with avatars but no
engines would silently export nothing. Walk a list of roots instead.

**Ingest pipeline** (`ProfileAvatarIngest`) — **do not re-encode GIFs, and do not
add an image package.** There is no `image` dependency in `pubspec.yaml`, and the
APK is already an open concern (85 → 160 MB). `dart:ui` can decode anything and
re-encode to PNG, but it cannot write an animated GIF, so a "downscale and
re-encode" pipeline would silently flatten every GIF to one frame.

- **Static images** (`.png/.jpg/.jpeg/.webp`): decode via `instantiateImageCodec`,
  downscale to 512×512, re-encode PNG, cap at 1 MiB.
- **GIFs**: accept as-is, no transcode. Validate by decoding, enforce a decoded
  dimension cap and frame-count cap, and hard-cap the file at **1 MiB** — well
  under the 4 MiB portable limit, so a full library can't blow the 64 MiB total
  or the 40 MiB restore guard. Oversized GIFs are rejected with a clear message
  rather than silently mangled.

**Carry a user image's `dominantColor` inside the `avatarKey` string — do not add
a column.** `file:avatars/<uuid>.gif#4A90D9`, computed once at ingest. The gate
can then paint its wash without touching the filesystem, and the colour still
reads correctly when the file is missing. (Procedural and bundled art need none
of this — their colour is a constant declared with the art itself.)

A new column looks tidier and is the wrong call on tvOS.
`exportRecoverySnapshot` serialises whole tables and stamps `schemaVersion`, and
`importRecoverySnapshot` rejects any snapshot whose version differs — there is no
envelope migration path. Since `profiles.db` itself lives in purgeable Caches on
Apple TV, a schema bump opens a window where an upgrade followed by a purge
*before the first post-upgrade checkpoint* leaves an envelope the app refuses,
dropping the user on the recovery screen. Encoding the colour in the existing
string keeps the schema frozen and rides every path `avatarKey` already travels.

### tvOS: catalog art and icons only — no user photos (decided)

Apple TV does not get personal photos or GIFs. The storage there is purgeable
(below), and everything needed to make a personal photo survive it — a
missing-file state, an automatic re-request from the phone, a "re-send" repair
affordance — is complexity the platform does not earn. Procedural art is code and
icons are assets, so neither can be purged: **restricting tvOS to those makes
avatars genuinely durable there and deletes the entire failure mode.**

(This is also why Tier 1 is procedural rather than a remote catalog. Catalog
images would cache into the very directory tvOS purges, so they would be durable
only while the network is up — weaker than what art-only is supposed to buy.)

This is one decision with **three enforcement points**. Miss any one and the
photo path reappears through the back door:

1. **Picker** — hide both *Choose image or GIF* and *Send from phone* on tvOS.
   The Avatar section offers art packs and icons only.
2. **Restore** — a package made on Android or phone can contain a `file:` avatar.
   On tvOS, do not materialise the file. Leave `avatar_key` intact so the same
   backup still works when restored on a phone; the tvOS device simply renders
   the fallback.
3. **Phone transfer** — the receiver must refuse an avatar payload on tvOS.
   Phase 6 shipping later must not quietly grant what the picker denies.

Because a `file:` key can therefore exist on tvOS without a file, the renderer
still needs the fallback below — but it is now a cosmetic edge case, not a
durability strategy.

### Why (the underlying constraint)

`AppStorage` redirects Documents to `Library/Caches` on a physical Apple TV
(Documents and Application Support are read-only there), and its own contract is
explicit: *"Caches is not a promise: tvOS may purge it under storage pressure …
nothing here should be treated as durable user data."*

This is what rules personal photos out. A file written there can vanish with no
user action, and there is no durable alternative: Documents and Application
Support are genuinely read-only on real hardware, and iCloud is out of scope.

Two facts that make the art-only decision cheap rather than a compromise:

- `user_profiles` is in `ProfileRegistry._recoveryTables`, so `avatar_key` — and
  the colour encoded in it — rides the Keychain envelope and survives a purge.
  Identity is durable even when files are not.
- Procedural art is drawn from code and icons are bundled assets, so a purge
  cannot touch either. A tvOS avatar comes back by itself, offline, with no user
  involvement and nothing to re-fetch.

There was never a file picker on tvOS either (`file_picker` is unusable there —
the recovery screen already hides its whole restore path behind
`if (!PlatformUtil.isTvOS)`), so nothing is being taken away that worked.

**Renderer floor, all platforms:** a missing avatar file is an ordinary state.
Render the colour from the key with the profile's initial — recognisably theirs,
never a broken tile and never an error log. It stays reachable even with art-only
tvOS, because a `file:` key can still arrive there by restore, and on any platform
a file can be deleted or truncated underneath us.

**Authorization.** Setting an avatar writes into the *target* profile's directory,
which may not be the actor's. Decide and enforce one rule: a profile may always
set its own avatar; changing another profile's requires `manageProfiles`. Validate
through `ProfileAuthorizationContext` the same way the editor's other writes do.

**Put the tvOS rule in one place.** All three enforcement points funnel through a
single avatar-import boundary — restore, phone transfer and the picker all end at
"materialise these bytes as this profile's avatar". Platform-check there, once,
rather than sprinkling `isTvOS` through the restore coordinator and the command
router where it will drift.

*Tests:* round-trip a GIF through export/restore with digest checks; oversize
rejected; avatars-without-engines exports non-empty (the early-return bug);
legacy icon keys still parse; unknown key degrades to role default; a traversal
key (`file:../…`) is rejected at parse and at restore. Plus the tvOS rules, which
are the likeliest to rot: restoring a package containing a `file:` avatar on tvOS
leaves the key and writes no file, and an avatar payload offered over the phone
channel is refused there.

---

## Phase 2 — `ProfileAvatarView`

One widget renders every kind — icon, procedural art, bundled art, static image,
GIF — used by the gate, the editor, the hub roster and the picker. This phase
also owns the **art registry**: `art:<id>` → painter + declared colour. Phase 1
defines the key grammar; the painters live here, because procedural art has no
storage at all.

**Focus-only animation is the contract**, but it means something different per
kind, and the mechanism must not be copy-pasted between them:

- **procedural art** — hold an `AnimationController` and simply don't tick it
  when unfocused. No decode, no cache, nothing to free. This is the cheap case,
  and it is the default set.
- **GIF** — unfocused shows a still first frame decoded once via
  `instantiateImageCodec` + `getNextFrame()` and cached by key; focused swaps to
  an animated `Image`.
- **static image, icon** — nothing to do; they never animate.

Only the GIF path needs the decoder discipline: never more than one animated
decoder alive at a time. Because Tier 1 is code rather than pixels, a full wall
of art avatars costs no decoders at all.

**Do not gate animation on `isAndroidTvCached`.** The TV perf playbook is about
applying *stricter* limits on TV, not about animating only there — phones and
desktops should animate normally. What is TV-gated is the tightening: on Android
TV, prefer the still frame more aggressively and honour the animate-on-gate
toggle as an off switch.

*Tests:* an unfocused GIF view instantiates no animated codec; the still frame is
cached across rebuilds; an unfocused procedural avatar leaves its controller
stopped; a focused one animates on phone as well as TV.

---

## Phase 3 — Add/Edit profile, categorized

The screen users liked in the mock. Restructures `edit_profile_screen.dart`
(799 lines) into six labelled sections; it is currently one flat column.

1. **Avatar** — art grid, *Choose image or GIF*, *Send from phone* (Phase 6;
   disabled until then), plus the animate-on-gate toggle. **On tvOS both
   *user*-photo entries are hidden**; the grid itself is unchanged there, since
   procedural and bundled art are code and assets, not user files.
2. **Identity** — name (**`TvTextField`**, house rule) and the create-time *Copy
   appearance and playback defaults* switch.
3. **Role** — three cards stating what each grants, replacing the bare dropdown.
   This is the feature-level control now, so it should say so.
4. **Lock** — PIN, Admin reset, lock-on-resume, auto-lock. Unchanged behaviour.
5. **Access** — the bulk of the screen, and the part that grows forever:
   - *Torrent engines* — which definitions get copied in;
   - *Shared connections* grouped by kind (Debrid & cloud / Addons / Trackers /
     Live TV, indexers & storage), each group with an *n of m* count and
     All/None, each borrowed resource expanding to its `ResourcePermission`
     chips (`use` fixed on, then `download`, `writeRemote`, `manage`,
     `revealSecret`, `share`), owned ones showing the transfer control.
6. **Data** — diagnostics, reset.

Behaviour is preserved throughout — this is grouping, labelling and one control
swap, not new authorization logic.

**Characterize before restructuring — there is no safety net.** `EditProfileScreen`,
`ProfilePickerScreen` and `ManageProfilesScreen` have **zero widget tests**; the
only profile UI test in the repo is `profile_gate_test.dart`, and it covers the
pure `shouldAutoEnterSoleProfile` function, not a screen. So "behaviour is
preserved" is currently an assertion with nothing enforcing it, on a 799-line
screen that carries authorization.

Write the characterization tests **first**, against the screen as it is today,
then restructure until they still pass. The ones that matter are the paths a
grouping change can silently break: saving writes
`ProfilePolicy.allAllowedFor(role)` while the policy editor is off; a resource
toggle persists the right grant bits; the ownership-transfer control appears only
with `manageConnections` and a non-child role; engine selection is disabled for
the active Admin's own profile; PIN validation still rejects out-of-range input.

*Tests:* the characterization set above, extended to the new layout.

---

## Phase 4 — Settings → Profiles hub

New top-level category beside Appearance and Connections. **A roster, and almost
nothing else** — it must not grow when a permission is added.

- Active-profile card → Edit / Switch.
- Roster grid + Create.
- Personalized Top Shelf — **platform-gated to tvOS**, invisible elsewhere.

That is the whole page. Two rows from the mock are deliberately **not** built:

- *Ask who's watching* — there is no launch pref today.
  `allowSingleProfileAutoEnter` is a hardcoded call-site argument in
  `profile_gate.dart`, so this row would be a **new** setting, not a
  simplification of existing ones. Keep today's behaviour hardcoded and add the
  pref only if users actually ask.
- *Lock again after sleep* — duplicates per-profile state. `UserProfile` already
  carries `lockOnResume` and `inactivityTimeoutMinutes`, both edited in Phase 3's
  Lock section. A device-wide row would be a second, conflicting home.

Sections are composed inline per layout (`SettingsSection` in
`settings_tv_layout.dart` and the phone screen) rather than declared in one
registry, so adding a category means editing both layouts plus the
settings-search leaf index. **Do not add a backup row here** — Backup already
owns "Back up profile" / "Back up all profiles" (`settings_screen.dart:3115`),
and a second entry point is how two divergent flows start.

Two questions the plan was carrying, now answered:

- **Legacy icons stay offered.** Existing profiles already reference
  `person`/`movie`/…, the keys must keep resolving regardless, and offering them
  costs one row in the art grid. Revisit only if the grid gets crowded.
- **Onboarding does not use this screen.** The first Admin is created
  programmatically by `ProfileBootstrap._createOrMigrateInitialAdmin`; no
  onboarding path constructs `EditProfileScreen`. Phase 3 therefore never has to
  render before a profile exists.

---

## Phase 5 — The gate

Replaces `profile_picker_screen.dart` (155 lines) behind `profile_gate_style`.

- Portrait tiles, unfocused desaturated and recessed, focused lifted with an
  inverse-white ring.
- **Ambient wash** from the focused avatar's colour — a declared constant for
  procedural and bundled art, and read from the key for user images. Either way
  no palette extraction and no file read ever happens on the TV.
- Lock badge, role caption, Add tile; Manage/Add in the footer.
- DPAD left/right, explicit `autofocus` on the first tile (house rule — never
  rely on default traversal), phone reflows to a 2-up grid.

**Preserve the management authorization ladder.** Nobody is signed in at the
gate, so Manage and Add cannot be plain buttons. `ProfileGate` already routes
them through a PIN/authorization challenge (`_pinForManagement`) before
`ManageProfilesScreen` opens. The redesign changes where those affordances sit,
never what they cost — a new picker that calls Manage directly would hand profile
creation and deletion to anyone holding the remote. Port the ladder first, style
it second.

**Invariant — the gate's isolation exemption.** The gate runs before any profile
is active, so it renders art for profiles that are locked and not the current
scope. Names already come from the registry, so metadata is not new; reading
*files* across profile directories is. Keep that exemption as narrow as it
sounds: the gate may resolve an avatar path from a registry-supplied
`avatar_key` and read that one file, and may touch nothing else belonging to a
profile it has not entered. Write it as a comment at the call site — otherwise a
later reader "fixes" the unscoped access and breaks the first screen.

*Tests:* exactly one tile is focused and only it animates; auto-enter of a sole
unpinned profile still bypasses the gate; and — the one that guards the ladder
above — **Manage from the picker reaches `ManageProfilesScreen` only after the
authorization challenge**, never directly. Today nothing asserts that at the UI
level, which is precisely why it is easy to lose in a rewrite.

---

## Phase 6 — Send an avatar from the phone

The only pleasant way to get a picture onto an **Android** TV — browsing a
filesystem with a D-pad is the alternative. Not needed for tvOS, which is
art-only, and the receiver must **refuse** an avatar payload there.

Reuse the existing chunked transfer (`ConfigCommand.debrifyChannelStart` /
`debrifyChannelChunk`) with a new payload kind — payload sealed once before
chunking, transport stays plaintext, same 1400 B UDP budget. Those two commands
are already exempt from the lease rate limiter in
`_dispatchAfterProfileAuthorization`, so a multi-hundred-KB image won't trip it.
Gate on `ProfileFeature.remoteTransfer`; run the received bytes through the same
Phase 1 ingest (never trust the sender's dimensions or size).

Note the route is **not** free: today a committed-profile install stages chunked
config into `_profileRemotePayload` (16 MiB cap) for a *setup import*, and an
avatar is not setup data. This needs its own command and its own handler that
writes straight to the target profile's avatars directory under the Phase 1
authorization rule — not a new key smuggled into the setup payload.

---

## Phase 7 — Appearance: gate style

Only if more than one concept ships. A picker page beside the other `*_style`
prefs, and flip `profile_gate_style` to the chosen default.

---

## Risks

- **GIF decode on weak boxes** is the main one. Focus-only playback plus the
  dimension / frame / 1 MiB caps are the mitigation; needs a real
  Xiaomi/Chromecast pass before the default flips.
- ~~tvOS avatar durability~~ — removed by the art-only decision. The residual
  risk is that the rule is enforced in only one of its three places (picker,
  restore, phone transfer) and personal photos leak back onto Apple TV.
- **Avatar files are the first binary user data in backups.** The codec exists and
  is validated, but its path resolution is generation-scoped and the `export()`
  early-return has to be fixed, or avatars silently vanish from packages — cheap
  bugs, expensive symptoms.
- **A `file:` avatarKey is attacker-controlled input** once packages can carry
  one. The validation in Phase 1 is not optional; without it this feature turns a
  restore into a path-traversal write.
- **Editor scope.** Access already dominates Edit profile and grows with every
  connection. If it gets unwieldy on a phone, split it to its own sub-page; the
  grouping in Phase 3 is designed so that split is a lift, not a rewrite.
- **No widget coverage on any of the three screens being changed.** This is the
  largest execution risk in the plan: two phases restructure authorization-bearing
  UI that nothing currently tests. Characterization tests first, in both Phase 3
  and Phase 5 — otherwise a regression here is silent and lands on the first
  screen users see.
- **Restore across versions.** A `file:` avatar restored onto a build that
  predates Phase 1 renders the default icon. Acceptable, but worth stating in
  release notes rather than discovering.
