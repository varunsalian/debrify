# Flutter video player screen refactor — plan

Written 2026-10-11 on `refactor/codebase` at `ed728b078` (the Android TV
player series merge). Follow [AGENTS.md](../../AGENTS.md).

Read first: [tv-player-activity-plan.md](tv-player-activity-plan.md) (the
phased player series this mirrors: per-phase sections, step T/0/0b/1,
exhaustive ownership checker with `--at`, collaborator pattern with narrow
Hosts, inert initializer proofs, Claude mutation sample, merged-tree gates,
end-of-series device checklist) and the Technique sections of
[debrify-tv-plan.md](debrify-tv-plan.md) and
[stremio-tv-plan.md](stremio-tv-plan.md) (the Dart verbatim checker, live
`context`/`mounted`/`setState`, lexical-scope guards, occurrence-level field
bindings, the source reader, analyzer identity baselines). This plan states
what differs.

Inventory: the analyzer member map at `ed728b078`
(`docs/refactoring/video-player-screen-deps.md`, produced with this plan;
every declaration with kind and line range) is the ledger every phase is
checked against. Each phase appends its own inventory there.

## Goal and scope

`lib/screens/video_player_screen.dart` is **18,106 lines** and **not
formatter-clean** (`dart format --set-exit-if-changed` changes it): 157
import/export directives (1–165, mixed package/relative, two `export`s of
`PlaylistEntry`/`ChannelEntry` kept for compatibility), then 8 top-level
declarations:

| Lines | Declaration |
|---|---|
| 167–169 | `_ManualSourceValidationFailure` |
| 171–176 | `_SeasonEpisodeSelection` |
| 178–200 | `_SubtitleApplyAttempt` (mutable) |
| 207–223 | `_IptvZapPage` |
| 229–254 | `IptvCatchupRequestGate` (public) |
| 268–454 | `VideoPlayerScreen` (public widget, ≈ 60 constructor parameters, static `readLocalResume`) |
| 456–18044 | `_VideoPlayerScreenState` — **17,589 lines**: ≈ 320 instance fields, 6 static fields, 358 methods, 44 getters, 167 `setState(` tokens, 239 `mounted` tokens, 173 `Timer` tokens |
| 18046–18106 | `_RandomChoiceTile` |

It is the Flutter (media_kit/libmpv) player used on phones, tablets,
desktop, tvOS and Android TV when the native player is off: player instance
and renderer/decoder fallback, open/startup pipeline (debrid direct, VOD
failover, startup gate), source switching (source sheet, Stremio, IPTV
sources, source playlists), the IPTV live pipeline (zap paging, guide
categories, catch-up/Start Over, live retune, audio preference, recording),
Stremio TV and Debrify TV channel navigation, playlist loading/resolve
(PikPak retry, metadata preload), episode navigation/shuffle/episode fetch,
resume restore/save, Trakt/Simkl/MDBList scrobbling and local completion,
subtitles (apply, auto-sync, addon fetch, identify-title search, priority,
track preferences), PiP/background, controls/TV keys/gestures/banners, sleep
timer/speed/aspect, the tracks sheet and the unified player menu, and a
1,172-line `build`.

The end state moves cohesive responsibilities into explicitly-dependent
collaborators under `lib/features/video_player/` while
`lib/screens/video_player_screen.dart` remains the **facade and composition
root**: the public `VideoPlayerScreen` (imported by 20+ production files and
14 test files, re-exports `PlaylistEntry`/`ChannelEntry`, public
`IptvCatchupRequestGate`), the State's lifecycle (`initState`,
`didChangeDependencies`, `didUpdateWidget`, `dispose` in their exact order),
the shared player instance and the wiring of collaborators.

**This is too large for one batch.** It runs as **ordered phases**, each on
its own branch `refactor/vplayer-pN` in worktree `../debrify-wt/vplayer`,
merged `--no-ff` into `refactor/codebase` and pushed to `private` before the
next phase starts. Each phase gets its own detailed section here, written
with then-current line numbers and Codex design-reviewed before it executes.

**Contract — unchanged by every phase:** the public constructor, its
parameters and defaults, `readLocalResume`, the two exports,
`IptvCatchupRequestGate`; the widget tree (types, keys, `const` placement,
order), focus nodes and traversal, TV key routing, gesture handling; every
`Timer`/`Future.delayed` duration; generation/ticket/token guards; every
provider callback the widget receives (call order, arguments, result-map
keys); media_kit configuration (`PlayerConfiguration`,
`VideoControllerConfiguration`, mpv properties, network tuning, audio
config); `MethodChannel` names/methods/arguments; storage keys and write
order; scrobble request order; resume save/restore semantics and the resume
write guard; lifecycle and teardown order (`dispose` is 207 lines — its
statement order is frozen); every user-visible string. No bug fixes ride
along; bugs found go to **Follow-ups**.

**Out of scope:** `lib/screens/video_player/**` (existing helpers and
sheets; several are oversized and get their own later goal), the native
players, `VideoPlayerLauncher`, Riverpod migration, localization, data
contracts, behaviour fixes and dead-code removal.

## Decisions taken before design review (Claude, 2026-10-11)

| # | Question | Decision |
|---|---|---|
| D1 | DI style. The user asked whether the Dart extractions use DI. | **Explicit constructor injection with narrow Hosts** (below), as in every prior Dart bridge. Riverpod is a **documented temporary exception**: converting a player's state to providers changes ownership, rebuild timing and teardown (AGENTS: ordered player teardown stays in its lifecycle coordinator) and cannot be proven by a move checker. Exit: a separate goal, *video player Riverpod migration* — per-session/profile notifiers for the extracted controllers, one controller per batch, behaviour-tested — recorded in Follow-ups with its prerequisites (this series' controllers and characterization tests). |
| D2 | Phasing vs one batch | Phased, as the TV activity (sequential; every phase edits the same file). |
| D3 | Formatting | The original is not formatter-clean. Phase 1 starts with a **format-only commit (a)** on the original with the token/comma proof (precedent: spotlight/catalog); (a) becomes R for phase 1. |
| D4 | Testability of the original | No test constructs `VideoPlayerScreen`; `_createPlayerInstance` constructs `mk.Player`/`mkv.VideoController` directly, so private members are unreachable (Dart has no reflection in `flutter test`) and the player is a native libmpv object. See "Characterization harness". |
| D5 | Destination | New feature `lib/features/video_player/`: `models/` and `application/` for service-free pure code, `presentation/legacy_video_player/` (the bridge) for collaborators that call services, storage, platform channels or the player. Registered in `check_search_architecture.py` like the other bridges. |
| D6 | `build` (1,172 lines) | Move-only cannot split one method. Decided in its own phase: either it stays in the facade (counted in the end-state exception) or moves whole to a builder with a size exception. Not before the controllers it calls have left. |

## Shared rules for every phase

1. **Move, don't rewrite.** Moved declarations keep bodies, comments and
   order token-for-token. Allowed edits are only those declared per
   declaration in the manifest: private → public renames of moved members
   and fields (`_sleepTimer` → `sleepTimer`), receiver qualification for
   state that stays in the State (`_player` → `_host.player`), the live
   `context`/`mounted`/`setState` forwarders, and in retained code, a call
   or field reference that now targets a collaborator
   (`_cancelSleepTimer()` → `_sleep.cancelSleepTimer()`). Every edit is
   declared, never inferred.
2. **Exhaustive Dart move checker with `--at`** (phase 1 step T). Like
   `check_kotlin_moves.py`, but over Dart, built on the existing analyzer
   14.3.0 tool package (`verbatim_ast.dart.txt` / `check_verbatim_moves.py`
   lexer and parser; no application dependency):
   - **Ownership.** Every declaration of the original at the phase base SHA
     (top-level declarations, class members including field initializers,
     constructors, getters/setters, statics, directives) gets exactly one
     fate: `retained`, `moved` (destination + declared renames/receivers) or
     `patched` (exact before→after token patches with occurrence counts; the
     whole patched declaration is compared). Unassigned, doubly assigned,
     surviving-after-move and unexpected new declarations are errors.
   - **Retained code is compared** token-for-token (only declared
     substitutions) and keeps its relative member order, so field
     initializer order cannot change silently. The facade's import list is
     validated against an exact reviewed list per phase; every destination's
     import list too.
   - **Partitioning** of the split State class: header, braces and ordered
     children; inter-member comments attach to the following member.
   - **Tokens** from the Dart scanner, comments included; whitespace outside
     literals normalised (Dart is not newline-sensitive, but trailing-comma
     and comment placement are tokens).
   - **Lexical scopes:** the `lexical_state_setters` and context guards and
     the `occurrence_field_bindings` guard (mandatory qualification) are
     reused, so a renamed field can never be captured by a same-named
     local/parameter, and a builder `context`/`setModalState` stays lexical.
   - **`--at <sha>`** checks a phase manifest against the tree at its merge
     commit, so every historical phase stays checkable after later phases
     move code again (`merge-checks.sh` runs all of them).
   - **Self-tests**: real-config positive fixture plus negatives — changed
     literal, dropped/edited comment, reordered statement, undeclared
     receiver/rename, a field captured by a same-named local, a builder
     `context` replaced by the host's, missing declaration, duplicate move,
     original+destination both present, unexpected new declaration,
     retained-body edit, field-initializer reorder, facade import change,
     destination import mismatch, a `patched` declaration with one extra
     edit, and `--at` against the wrong SHA.
   Before any production move it must self-compare R with an all-`retained`
   manifest (zero diffs, every declaration classified).
3. **Collaborator pattern** (from the first stateful phase):
   - `class VpXController` (or a precise noun) in the bridge, constructed
     **once** in a State field initializer slot-anchored at the position of
     the first moved field it owns, with an **inert constructor** (assigns
     fields, starts nothing — proven per phase, because a field initializer
     runs before `initState`, earlier than the original statements).
   - It owns the fields of its responsibility (moved, renamed public). The
     State reaches them as `_x.field` (registered receiver).
   - Everything it needs from the State goes through a **narrow Host**: an
     `abstract interface class VpXHost` declared beside the controller,
     implemented by a small private adapter class in the facade library
     (`_VpXHostAdapter(this._s)`) whose members are one-line forwarders to
     the live State member (`bool get mounted => _s.mounted;`,
     `void setState(VoidCallback fn) => _s.setState(fn);`,
     `mk.Player get player => _s._player;`). Forwarders are computed (never
     cached), so values are read at the original moment. Each Host lists
     only what its controller reads (checked: every Host member has at least
     one reader; no Host exposes the whole State). Adapters are frozen in
     the manifest as scaffolding with exact bodies.
   - `context` stays live: `_host.context` forwards to the State's `context`
     at the call site; builder-local `context`s stay lexical.
   - Cross-collaborator calls go through the Host (wired by the facade), not
     by collaborators importing each other's state, unless the phase
     section declares an owner/child pair.
   - Collaborators are disposed only where the original disposed their
     resources: `dispose` keeps its statement order; a moved timer cancel
     becomes `_x.cancelFoo()` at the same position.
4. **Characterize the original first (step 0)**, through the harness below:
   widget tests that pin the phase's observable behaviour on the original
   (rendered widgets, focus, key results, timers via `fake_async`/`tester.pump`,
   fake player calls, captured provider callbacks, storage writes through the
   existing test doubles, method-channel invocations via
   `TestDefaultBinaryMessengerBinding`), each proven by an assertion-failing
   **mutation of the original** in a detached worktree under the evidence
   dir. Then Claude's independent mutation sample (≥ 75 % killed, otherwise
   step 0b closes the gaps and Claude samples again). Coverage sweep: every
   moved member is reached by at least one characterization test or is
   listed with a reason (unreachable without a device, dead) in the phase's
   coverage matrix.
5. **Tests that read source text** (`manual_source_validation_contract_test`,
   `android_tv_mdblist_progress_source_test`, `media_server_*` (3),
   `playback_startup_view_test`, `player_auto_next_routing_test`,
   `playback_checkpoint_contract_test`, `theme/source_guard_test`, and the
   Debrify TV / Stremio TV / recordings fixtures and handoff helpers) keep
   their purpose: when an anchored range moves, the test is retargeted in
   the same commit to a **per-declaration source reader** that follows the
   manifest (precedent: Debrify TV), with an equal-or-stronger assertion;
   each retarget is listed in the deps report. Never delete an assertion.
6. **Analyzer identities.** Each phase records the analyzer diagnostics of
   the original (root config) by identity (rule, enclosing member, message)
   and a rename/receiver probe; new destinations live under `lib/features`
   (stricter config: `directives_ordering`, etc.), so each surviving
   pre-existing diagnostic gets its `analyzer_allowlist.txt` entry in the
   commit that creates its file. No `const`, key or suppression changes.
7. **Gates per phase** (evidence under
   `<git-common-dir>/refactor-evidence/vplayer/pN/`):
   - Full Flutter suite via `suite_evidence.py` at the base, after step 0
     (new baseline) and at the gate, compared by test identity; known
     load-sensitive flakes rerun in isolation with a NOTE, never allowlisted.
   - `dart format` of changed Dart files, `flutter analyze` (identities),
     `check_file_sizes.py` (the facade baseline lowered with `--update`;
     every new file ≤ 800 lines, or ≤ 500 preferred, unless a documented
     exception), `check_search_architecture.py`, every Dart manifest
     self-test with an isolated `--parser-package`, all historical phase
     manifests with `--at`.
   - At the gate: `flutter build apk --release` and `flutter build macos
     --release` succeed (no install, no run); gate commit message contains
     `gate`.
   - Never `flutter run`/install on any device; no emulators.
8. **Device checks** are not gates; each phase lists what a human checks at
   the end of the series (phone, Android TV with the Flutter player, tvOS,
   desktop), aggregated into the end-of-series checklist.
9. **Codex** (gpt-6.1-sol, xhigh, `~/bin/codex-run`) reviews each phase
   design until "No P1s", executes step T/0/0b/1, and a fresh Codex session
   reviews the gated range; Claude reviews too and merges.

## Characterization harness

The State is unreachable from tests without help, and the player is native.
Options, in order of preference — **the design review must settle this**:

- **(H1) Test-only seam checkpoint (recommended).** One reviewed commit
  before phase 1 step 0, the only application change before any move: a
  `@visibleForTesting` static hook on the screen library,
  `VideoPlayerScreenTestHooks`, consulted only in `_createPlayerInstance`
  (and wherever else the review proves a native call is unavoidable in a
  widget test — e.g. `MediaKit.ensureInitialized`, window manager, wakelock)
  so a test can supply a fake `mk.Player`/`mkv.VideoController` pair. With
  the hook null (production and release), the executed code is
  token-identical to the original; proven by the checker (a single
  declared `patched` declaration) plus a release-build check that the hook
  is never set outside `test/`. The checkpoint becomes the ORIGINAL for
  behaviour; every later mutation and proof runs against it.
- **(H2) Real libmpv in tests.** `/opt/homebrew/lib/libmpv.dylib` exists
  locally but not on CI/Linux runners; real decoding in widget tests is
  timing-dependent. Rejected as the primary harness; may supplement a
  smoke test locally.
- **(H3) Source-text characterization only.** Rejected: AGENTS says
  source-text tests are not behaviour tests.

The harness (`test/features/video_player/support/`) provides a fake player
(streams the State subscribes to, recorded `open`/`seek`/`setRate`/
`setSubtitleTrack`/`setAudioTrack`/`setProperty` calls), a widget pump with
the existing storage/service fakes, a method-channel recorder, and helpers
to drive TV keys, taps and timers.

## Phase map (risk-ordered)

Line numbers at `ed728b078`; each phase section re-measures. ≈ lines out of
the facade.

| Phase | Content | ≈ out | Risk |
|---|---|---|---|
| 1 | Format commit; Dart move checker (`--at`, exhaustive); harness seam (H1) + harness; top-level types (`_ManualSourceValidationFailure`, `_SeasonEpisodeSelection`, `_SubtitleApplyAttempt`, `_IptvZapPage`, `IptvCatchupRequestGate` re-exported, `_RandomChoiceTile`) and State-pure helpers (`_format`, `_pad2`, `_generateFilenameHash`, `_normalisePosterUrl`, `_normalisedContentType`, `_randomStartOffset`/`_percentStartOffset`, `_dockGeometrySignature`, …; exact list from the step-0 purity proof) | 400 | low |
| 2 | Trackers: Trakt/Simkl/MDBList scrobble + heartbeats, analytics heartbeat, local completion, tracker percent helpers (1797–2750 minus skip segments) | 900 | med |
| 3 | Self-owned features: sleep timer, skip segments, speed/aspect/orientation, PiP + background/wakelock (1797–2040, 11635–11882, 13739–14030) | 800 | med |
| 4 | Subtitle engine: auto-sync, sync overlay, subtitle settings, apply + diagnostics + failure (2940–3090, 5014–5200, 6380–6630) | 700 | med |
| 5 | Subtitle sources and preferences: track preference restore, default audio/subtitle language, forced, addon fetch/auto-select, Stremio download, priority (17164–18044) | 880 | med |
| 6 | Identify title + subtitle search sheet; tracks sheet; unified player menu (15932–17162) | 1,230 | med |
| 7 | Resume: keys, restore, seek/verify/landing, enhanced state, save + write guard (12093–12905) | 810 | high |
| 8 | IPTV recording (7691–8297) | 610 | med |
| 9 | IPTV zap paging, guide categories, Start Over/catch-up, live retune (759–1272 IPTV members, 6627–7537) | 1,100 | high |
| 10 | IPTV channel switch, live stream open, audio preference, stream error/recovery (7382–7690, 8298–8562) | 600 | high |
| 11 | Startup: debrid direct, startup VOD, VOD failover, startup gate (8563–9240) | 680 | high |
| 12 | Source switching: source sheet, source playlist/Stremio/IPTV source switch (9201–9820) | 620 | high |
| 13 | Stremio TV and Debrify TV channel navigation (9821–10330) + Debrify/IPTV banners (13414–13570, 14124–14236) | 700 | high |
| 14 | Episode navigation: ended, next/previous, shuffle/random, series next, title/subtitle info (5210–6360, 10332–10478) | 1,300 | high |
| 15 | Playlist load/resolve, video metadata wait, PikPak retry, metadata preload/save (10479–11634) | 1,150 | high |
| 16 | Episode fetch + synthetic guide (14242–14736) | 500 | high |
| 17 | Player engine I: audio/output lease/effects, passthrough, tvOS remedy/display match, decoder/renderer fallback (2750–3263, 4076–4692) | 1,200 | highest |
| 18 | Player engine II: `_initializePlayer`, open media, network tuning, instance subscriptions, startup watchdog (3264–4075, 4693–4978) | 1,350 | highest |
| 19 | Controls runtime: auto-hide, TV bar/scrub, TV keys, overlays, gestures (12907–13738) | 830 | high |
| 20 | `build` decision (D6), end-state exception, completion audit, CI structure job | — | — |

Expected end: the facade holds the public widget, lifecycle methods, the
shared player fields, Host adapters and wiring, and possibly `build`. Its
size is reassessed at phase 20; anything over 800 lines gets a documented
end-state exception with remaining responsibilities and an exit milestone.

## Phase 1 — format, checker, harness, top-level types and pure helpers

Branch `refactor/vplayer-p1` off `ed728b078`. Evidence
`refactor-evidence/vplayer/p1/`.

### Steps

- **(a) Format-only commit** `style(vplayer): format the original video
  player screen` — `dart format` of the facade only, with the token/comma
  proof (scanner tokens identical except trailing commas the formatter
  adds/removes; precedent tooling). R = (a).
- **Step T — tooling.** The exhaustive Dart move checker with `--at`
  (shared rule 2) as `dev/tool/check_dart_moves.py` (reusing the
  analyzer tool package; no new application dependency), manifests in
  `dev/tool/dart_moves/vplayer_pN.json`, real-config fixtures and every
  negative listed in rule 2; all-`retained` self-compare of R; every
  existing Dart manifest self-test still passes.
- **(S) Harness seam checkpoint** (H1, if the review keeps it): the hook,
  its manifest entry as the only `patched` declaration(s), proof that
  release/profile code paths are token-identical with the hook null, and a
  guard test that no file under `lib/` assigns the hook.
- **Step 0 — characterization of the original (at S).** Harness smoke tests
  (screen builds with a fake player for a direct URL, a playlist, an IPTV
  channel list, a Stremio TV channel; disposes cleanly; no pending timers);
  then tests for the phase-1 moves: the five types' observable effects
  (`IptvCatchupRequestGate` semantics incl. stale tickets; the
  `_RandomChoiceTile` rendering inside the random-playback menu; subtitle
  apply attempt lifecycle through a subtitle selection; zap page
  window/offset through an IPTV zap) and each pure helper through its
  caller. Mutation proofs on S for every test; coverage matrix.
- **Claude sample** (≥ 75 %), **step 0b** if needed.
- **Step 1 — moves.** Types to `lib/features/video_player/models/`
  (`IptvCatchupRequestGate` keeps its name and is re-exported from the facade
  so the public import path still works; private types become public with a
  `Vp` prefix only if they cross files, as declared renames, or stay private
  with a `typedef` per the spotlight precedent — the review picks one rule
  for the series); `_RandomChoiceTile` to `presentation/`; pure helpers to
  `application/` as top-level functions (declared renames), called from the
  retained code (declared substitutions).
- **Gate** (commit message contains `gate`), **independent Codex review**,
  merge, merge checks, push.

### Phase 1 device checklist (end of series)

Random-playback menu tiles render and select on phone and TV; IPTV
catch-up/Start Over request cancellation still wins over a slow lookup.

## Follow-ups

- **Video player Riverpod migration** (D1 exit): controllers become
  per-session/profile notifiers, one per batch, behaviour-tested; requires
  this series' collaborators and characterization tests.
- `lib/screens/video_player/**` oversized files (`iptv_channel_sheet` 3,667,
  `tracks_sheet` 2,197, `player_menu_panel` 1,844, …) — their own goal.
- Localization of player strings.

## Progress

(none yet)
