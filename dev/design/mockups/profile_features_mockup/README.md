# Profile features — questionnaire (replaces the switch wall)

Mock: `index.html` (open locally, or
https://claude.ai/code/artifact/0672e477-3c3b-4a6f-8bc1-fadc7fe0d96e)

## Idea (2026-08-16)

The per-connection six-permission grants (Use / Download / Send remotely /
Manage / Reveal secret / Share onward) confused even the author. Decision:

- Sharing a connection becomes **binary** (shared or not).
- Three former grant bits become **rules, not choices**: secrets are
  owner-only, manage/delete is owner-only, share-onward is deleted.
- Access control moves to **profile-level feature toggles**, configured as a
  **four-step questionnaire** whose answers the role preset pre-fills —
  picking Kid means the parent can just Next×4.

## v1 features (8) and the four questions

0. **Identity** (not a question — before the questionnaire): name, avatar
   (icons / living art / GIF-photo via the existing avatar system),
   optional PIN
1. **Role** (= preset): Admin / Member / Kid
2. **Search power**: by title in their catalogs (always on for everyone)
   ⟷ plus raw keyword search → drives ONLY Keyword search
3. **Sources pages** (multi-select tiles): Debrify TV / Stremio TV /
   Live TV (IPTV) / YouTube
4. **Abilities** (toggle-cards): Downloads & recording, Remote,
   Manage own sources (whether the profile edits its OWN addon/engine
   roster — the admin curates any profile's roster regardless, via
   Review → "Edit sources" / Edit Profile, over the existing resource
   grants), and **Cloud files** (browse raw account file lists —
   preset: Admin ON, Member OFF, Kid OFF; a shared debrid account's
   file list is the owner's viewing history)

v1 = ten features. Backup & transfer remains the fast-follow.

Revised 2026-08-16 after two gaps were called: catalog search is NOT a
permission (safety = the curated source list, not a search toggle), and
"Addons page" was really two things — the profile's self-management
(now the Manage-own-sources ability) vs the admin's per-profile source
curation (always available to admins, surfaced on Review).

An **admin Sources editor** frame (reached from Review → "Edit sources" or
Edit Profile) shows per-profile checklists over EVERY connection kind —
addons, debrid & cloud, trackers (Trakt/Simkl/MDBList), Live TV sources,
torrent engines & indexers (the full ConnectionResourceType roster) — the existing resource grants as a
human UI. Everything starts ENABLED for every profile EXCEPT trackers — watch
history is personal, so Trakt/Simkl/MDBList default off and each profile
connects their own (sharing stays one tick away). Otherwise restriction
is the admin's opt-in act, and engines are first-class: they resolve streams for
titles, not just keyword results, so they matter even when keyword search
is off. Copy rule: profile pronouns are the NAME or they/them — never
gendered (2026-08-16 call).

Review screen speaks "Can / Can't" chips; the raw eight switches live only
in a collapsed **Fine-tune** drawer. Editing later lands on Review with
"Re-run questions" available.

Presets: Admin & Member = all 8 on (their difference is the role-bound admin
features: manage services / manage profiles). Kid = Home shelves + Debrify
TV only.

## Rules

- Preset = prefilled, never locked; divergence is unceremonious.
- Off = invisible everywhere (tab, Home rows, settings search, deep links,
  remote commands) — but enforcement stays at the operation boundary
  (`ProfileFeature`); hiding is a courtesy per the threat model.
- Page gates are not content safety; the rating ceiling remains its own
  future feature (isolation audit's open item).
- Fast-follow pair: Cloud files, Backup & transfer (step 4 grows two cards).
- TV: same four steps, cards as DPAD rows, one question per screen.

## Audit (2026-08-16) — gaps & loopholes found before build

Role-locked safety rails (hard-bound to role == child in ProfilePolicy,
never toggles): Debrify TV NSFW filter forced ON and VIEWER-SCOPED
(evaluated at browse/play against the active profile — an admin-authored
NSFW-allowed channel must still filter for a Kid viewer); Reddit NSFW
forced off; future rating ceiling defaults on.

1. Kid Debrify TV is WATCH-ONLY — channel create/edit hidden for child
   role (keyword channels are keyword search by the back door).
2. Kid Review screen nudges a sources trim ("Maya currently has every
   source — review?") — all-on default + always-on catalog search means
   untrimmed Cinemeta; real fix remains the rating ceiling.
3. Reddit page = 11th feature toggle (A ✓ / M ✓ / K —).
4. Deep links join the reach sweep (magnet/debrify:// actions check
   features); consider Kid quick-play-only source browsing (polish).
5. Defined behavior: sources added later inherit the default (on,
   trackers off) for every profile — trimming is per-resource, not a
   standing mode.
6. Reach sweep explicitly includes settings pages + settings-search
   entries of gated features.

Verified sound: remote lease scoping, admin-only comprehensive export,
wall clearing startup conveniences, admin-gated questionnaire/editor,
engines-for-kids, profile-scoped playlists/CW, owner-only secrets and
manage/delete.

### Dispositions (2026-08-16, owner review)

Findings 1, 2, 4: ACCEPTED AS-IS — no watch-only mode, no trim nudge, no
deep-link gating. Rationale: household courtesy-gating threat model; the
NSFW rail (viewer-scoped, role-locked, applies to results/playback) plus
the page toggle is the defense for 1; the admin's ability to trim IS the
mitigation for 2; remote commands are already lease-checked, and manual
magnet-opening is outside the protection tier for 4.
Finding 3: MOOT — the Reddit page no longer exists. NOTE for the build:
reddit prefs + ConnectionResourceType.reddit are vestiges of the removed
feature; the Sources editor must NOT grow a section for them.
Standing items: the viewer-scoped role-locked NSFW rail, rule 5 (new
sources inherit the default), rule 6 (settings in the reach sweep).
