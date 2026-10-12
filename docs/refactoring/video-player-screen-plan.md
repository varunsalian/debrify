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
| D1 | DI style. The user asked whether the Dart extractions use DI. | **Explicit constructor injection with narrow Hosts** (below), as in every prior Dart bridge. Riverpod is a **documented temporary exception**: converting a player's state to providers changes ownership, rebuild timing and teardown (AGENTS: ordered player teardown stays in its lifecycle coordinator) and cannot be proven by a move checker. Exit: a separate goal, *video player Riverpod migration* — per-session/profile notifiers for the extracted controllers, one controller per batch, behaviour-tested — **together with the service/data ownership exit** (the bridge calls services, storage, channels and the player directly; data contracts for resume, trackers, subtitles, sources and IPTV must replace those calls, since converting presentation bridges to Riverpod alone would not resolve the layering exception). Recorded in Follow-ups with its prerequisites (this series' controllers and characterization tests). |
| D2 | Phasing vs one batch | Phased, as the TV activity (sequential; every phase edits the same file). |
| D3 | Formatting | The original is not formatter-clean. Phase 1 starts with a **format-only commit (a)** on the original with the token/comma proof (precedent: spotlight/catalog); (a) becomes R for phase 1. |
| D4 | Testability of the original | No existing test **mounts and characterizes the player State** (tests construct `VideoPlayerScreen` only to inspect launch contracts, and route observers intercept before its State mounts — `iptv_channel_sheet_responsive_test.dart:61`, `stremio_tv_fixture.dart:55`). `initState` initializes native media_kit (1753) and `_createPlayerInstance` constructs `mk.Player`/`mkv.VideoController` directly; private members are unreachable (no reflection in `flutter test`). See "Characterization harness". |
| D5 | Destination | New feature `lib/features/video_player/`: `models/` and `application/` for service-free pure code, `presentation/legacy_video_player/` (the bridge) for collaborators that call services, storage, platform channels or the player. Registered in `check_search_architecture.py` like the other bridges. |
| D6 | `build` (1,172 lines) | Move-only cannot split one method. Decided in phase 25: either it stays in the facade or moves whole to a builder; either way a **bounded, measured exception** (exact line count registered at creation, shrink-only ratchet in `file_size_baseline.txt`) with a named exit: a behaviour-level `build` decomposition into layout widgets with goldens, its own goal. Widget + lifecycle are already ≈ 580 lines, so the facade's end state is registered by measurement, never as an unspecified size. |

## Shared rules for every phase

1. **Move, don't rewrite.** Moved declarations keep bodies, comments and
   order token-for-token. Allowed edits are only those declared per
   declaration in the manifest: private → public renames of moved members
   and fields (`_sleepTimer` → `sleepTimer`), receiver qualification for
   state that stays in the State (`_player` → `_host.player`), the live
   `context`/`mounted`/`setState` forwarders, and in retained code, a call
   or field reference that now targets a collaborator
   (`_cancelSleepTimer()` → `_sleep.cancelSleepTimer()`), and removal of
   a `static` modifier when a static member becomes a top-level function
   (exact opt-in per declaration; negatives for an extra modifier or body
   edit — the existing core only supports *added* static ownership,
   `check_verbatim_moves.py:163`). Every edit is declared, never inferred.
   The shared guards (`occurrence_field_bindings.py:37` recognises only
   `_deps.alias()`) get explicit opt-in support for `_host` property
   getters/setters, compound assignments/increments and owner-identity
   substitutions; existing manifests keep their behaviour.
2. **Exhaustive Dart move checker with `--at`** (phase 1 step T).
   `dev/tool/check_dart_moves.py` is a **thin ownership/history layer**
   that invokes the existing comparison core — `check_verbatim_moves.py`
   (analyzer 14.3.0 declarations and scanner tokens, coverage and moved-body
   comparison) and the scope/binding protections that enter through
   `check_settings_moves.py` (`occurrence_field_bindings`,
   `lexical_state_setters`, context guard, live getters). **No second
   normalization implementation.** It adds, like `check_kotlin_moves.py`:
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
     commit, reading manifests, sidecars, import lists and initializer
     evidence **from that same revision** (`merge-checks.sh` runs all of
     them).
   - **Current-tree protection of earlier destinations** (the Kotlin
     precedent, `check_kotlin_moves.py:363` + `kotlin_move_partition.py:61`):
     every file created by an earlier phase is checked in the **current**
     tree against its frozen content, or against exact scoped patches when a
     later phase legitimately rewires it (e.g. a Host gains a member, a call
     is re-pointed). Required coverage is derived from all historical
     manifests. Negative: edit a phase-1 destination while the current
     facade is unchanged → fails.
   - **Scaffolding is frozen exhaustively**: every Host interface, adapter,
     controller field list and initializer body, constructor, and the
     destination's declaration order.
   - **Formatting**: the format commit (a) and any formatted moved code may
     differ from the original only by **AST-identified optional trailing
     commas** (insert/delete sites recorded; a required singleton-record
     comma is rejected), applied after receiver substitutions too; formatter
     idempotence and any diagnostics introduced by formatting are recorded.
   - **Self-tests**: real-config positive fixture plus negatives — changed
     literal, dropped/edited comment, reordered statement, undeclared
     receiver/rename, a field captured by a same-named local, a builder
     `context` replaced by the host's, a lexical `setSheetState`/
     `setDialogState` (16227, 16445) replaced by the host's `setState`, an
     owner-identity `this` left unsubstituted in moved code, a captured
     local turned into a live host read, a Host write/increment
     (`_host.x++`) mis-targeted, missing declaration, duplicate move,
     original+destination both present, unexpected new declaration,
     retained-body edit, field-initializer reorder, facade import change,
     destination import mismatch, a `patched` declaration with one extra
     edit, and `--at` against the wrong SHA.
   Before any production move it must self-compare R with an all-`retained`
   manifest (zero diffs, every declaration classified).
3. **Collaborator pattern** (from the first stateful phase):
   - `class VpXController` (or a precise noun) in the bridge. **Dart
     construction rule** (Kotlin slot construction does not transfer: a
     Dart field initializer cannot reference `this`, and `late final` with
     an initializer is lazy, so its position guarantees nothing):
     collaborators are `late final` fields **assigned eagerly in one State
     constructor body** (`_VideoPlayerScreenState() { … }`, added in the
     first stateful phase as frozen scaffolding, extended one line per
     collaborator in later phases). It runs after every field initializer
     and before `initState`. Constructors are **inert** (assign fields,
     start nothing).
   - It owns the fields of its responsibility (moved, renamed public). The
     State reaches them as `_x.field` (registered receiver). Relocating a
     field changes when its initializer runs (from its slot among the
     State's initializers to the collaborator's construction), so **every
     relocated initializer gets its own inertness proof** (a literal,
     `const`, or an allocation with no side effects: `FocusNode()`,
     `ValueNotifier(x)`, `Completer()` — listed per phase; **not** `Random()`, whose
     seeding advances a shared PRNG, so the State's `Random()` (517) stays
     State-owned unless a phase proves its ordering immaterial). Collaborator
     constructors **and their field initializers** never read the Host (the
     State constructor runs before Flutter assigns `widget` and `context`).
     Original eager/lazy modifiers are preserved (`late final
     _iptvLiveRecovery` 735 stays lazy).
     Effectful or order-sensitive initializers (anything that registers,
     schedules, reads a service, or whose evaluation order with another
     initializer is observable) **stay State-owned**.
   - Everything it needs from the State goes through a **narrow Host**: an
     `abstract interface class VpXHost` declared beside the controller,
     implemented by a small private adapter class in the facade library
     (`_VpXHostAdapter(this._s)`; library privacy lets it reach the State's
     private members) whose members are one-line forwarders to the live
     State member (`bool get mounted => _s.mounted;`,
     `mk.Player get player => _s._player;`, setters for writes,
     methods for calls). **`setState`** is forwarded through a State-owned
     private method (`void _vpSetState(VoidCallback fn) => setState(fn);`,
     frozen scaffolding), never by calling the protected `setState` from
     the adapter. Forwarders are computed (never cached), so values are read
     at the original moment; **originally captured locals stay locals** —
     forwarding never turns a snapshot into a later read. Each Host lists
     only what its controller reads (checked: every Host member has at least
     one reader; no Host exposes the whole State). Adapters are frozen in
     the manifest as scaffolding with exact bodies.
   - **Owner identity.** A moved `this` that identifies the State to a
     service (`PipService.isOwner(this)` 11637,
     `PlayerVisibility.playbackState(this, …)` 3925, any `identical(this,`,
     listener registration keyed by `this`) becomes a narrowly named Host
     member returning the State (`host.pipOwner`, `host.visibilityOwner`),
     pinned as a declared substitution by occurrence. An unsubstituted
     `this` in moved code that reaches such a call is a checker error.
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
5. **Tests that read the player source** keep their purpose. The complete
   list of direct readers (design review round 1):

   | Test | Anchors that must survive |
   |---|---|
   | `test/manual_source_validation_contract_test.dart:230` | explicit-selection validation; rejected-candidate progress suppression; outgoing-stream restoration; playlist/PikPak exhaustion |
   | `test/android_tv_mdblist_progress_source_test.dart:148` | carried TVMaze identity; tracker-progress getters; metadata readiness; rewatch resume suppression |
   | `test/media_server_service_test.dart:1459` | final authorization barrier; source propagation; validation arming after async setup |
   | `test/media_server_player_resume_test.dart:105` | guarded `readLocalResume` selection; no direct URL fallback there |
   | `test/media_server_watch_player_wiring_test.dart:24` | prepare/authorize/open order; watch epoch; commit; reporting guards; close and EOF |
   | `test/playback_startup_view_test.dart:8` | opaque non-interactive PiP startup shield and its transition rendering site |
   | `test/player_auto_next_routing_test.dart:16` | EOF routing order, shared next route, navigation/sleep cancellation, resume suppression |
   | `test/services/webdav_sync/playback_checkpoint_contract_test.dart:18` | pause/seek persisted checkpoints, save lock, guards rechecked after queueing |
   | `test/theme/source_guard_test.dart:37` | frozen player paths, construction containment, route guards, forbidden theme reads |

   Step 0 of phase 1 adds a **per-declaration source reader**
   (`test/features/video_player/support/vp_source_reader.dart`) that
   resolves a declaration by name through the phase manifests, **validates
   current ownership and the body against the checker before returning
   it**, and chains relocation across phases; it never satisfies an
   assertion with historical text. When an anchored declaration moves, its
   test is switched to the reader in the same commit with an
   equal-or-stronger assertion, listed in the deps report (old anchor → new
   anchor). The theme scans need the **current destination files**: the
   frozen-path list in `dev/tool/theme_surface_manifest.txt:26`
   (`p2_player_dart`), `dev/tool/theme_rendered_set.py:57` and the exact
   assertion in `source_guard_test.dart` are extended with each new
   `lib/features/video_player/**` file in the commit that creates it. The
   Debrify TV / Stremio TV / recordings fixtures and handoff helpers are
   public-widget contract consumers, not source readers: their checks are
   preserved and not retargeted. Never delete an assertion.
6. **Analyzer identities.** Each phase records, by enclosing declaration
   and **multiplicity**, the diagnostics of the original (root config), of
   the formatted original, under the strict `lib/features` config, and of
   a rename/receiver probe; baseline and probe combine by maximum per
   identity. Each surviving pre-existing diagnostic gets its
   `analyzer_allowlist.txt` entry in the commit that creates its file. The
   global allowlist matches as a set and ignores infos
   (`check_analyzer_allowlist.py:40`), so phase 1 adds a **scoped identity
   comparator** (`dev/tool/check_vplayer_analyzer.py`) that enforces the
   recorded identities and counts, infos included, for the facade and every
   `video_player` destination. No `const`, key or suppression changes.
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
     `gate`. Baselines are reused across mechanical moves within a phase
     (AGENTS); the broad suite and builds run at the gates and the
     integration milestones below.
   - **CI from the first production file** (phase 1): `video_player`
     registered in `check_search_architecture.py` `FEATURES` with the exact
     legacy bridge, a facade back-import prohibition (no
     `lib/features/video_player/**` file imports the facade), pure
     `models/`/`application/` boundaries, scoped compatibility imports and
     size caps; the facade and new files added to the explicit
     format/analyze lists in `.github/workflows/checks.yml:70`; the Dart
     move checker self-test and current-tree check (with history, so
     `fetch-depth: 0`) and the analyzer comparator in CI; every new
     characterization file added to `ci_behavior_tests.txt` (the gate job
     runs that curated list — a `gate` message alone adds no tests).
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

- **(H1) Test-only seam checkpoint (chosen; design review round 1).** One
  separately reviewed commit **S** before phase 1 step 0, the only
  application change before any move: one `@visibleForTesting` hook object,
  `VideoPlayerScreenTestHooks`, with **exactly three interception points**:
  1. the `MediaKitInit.ensureInitialized()` statement in `initState`
     (1753) → test no-op/recorder;
  2. the `mk.Player(configuration: …)` expression in `_createPlayerInstance`
     (2914) → a factory **receiving the original configuration** (including
     its `ready` callback);
  3. the `mkv.VideoController(player, configuration: …)` expression → a
     factory receiving the same player and the original video
     configuration.
  The surrounding statements keep their order: `_player` assignment,
  `_playerCreated`, controller construction, tvOS remedy, subscriptions,
  decoder observers, aspect zoom. No early return, no objects created up
  front. **Installation**: one frozen static installer whose assignment
  happens only inside an `assert` (so it is compiled out of
  release/profile), preceded by an explicit non-assert check that throws if
  called when `kReleaseMode || kProfileMode`, and additionally gated on a
  test-only compile-time flag (`bool.fromEnvironment('DEBRIFY_VP_TEST_HOOKS')`)
  so an ordinary debug app cannot install it; the flag is registered in the
  test and CI commands that run the harness. The source guard permits
  exactly the installer's own assignment and rejects every other assignment
  of the hook and every reference to the installer under `lib/`. **Proof**:
  two `patched` declarations (`initState`, `_createPlayerInstance`) with
  three exact before→after patches, plus the added scaffolding (hook
  class, installer, interception helpers) frozen separately; the token
  proof covers the helper bodies and installer; each default path calls
  the original operation **exactly once**, evaluates the configuration
  once, and keeps assignment and guard order. A release build alone proves
  neither property. S becomes the ORIGINAL for
  behaviour; every later mutation and proof runs against S.

  **Fakes** (`test/features/video_player/support/`), all via `implements`
  (extending or calling the vendored native constructors —
  `packages/media_kit_patched/lib/src/player/player.dart:101`,
  `packages/media_kit_video_patched/lib/src/video_controller/video_controller.dart:72`
  — would create native resources):
  - `FakePlayer implements mk.Player`: `open`, `stop`, `play`, `pause`,
    `playOrPause`, `seek`, `setRate`, `setVolume`, `setAudioTrack`,
    `setSubtitleTrack`, `dispose`, `handle`; a coherent `PlayerState` and
    broadcast streams for every stream the State subscribes to (log,
    error, video params, position, duration, playing, completed,
    buffering, the selected `track` and the available `tracks` — `_bindPlayerInstanceSubscriptions` 3790; the conditional audio-policy subscription reads `stream.track` 3878) and that
    the real `mkv.Video` subtree consumes (width, height, playing,
    subtitle — `video_texture.dart:303`); recorded calls; controllable
    delayed/failed operations and disposal completion.
  - A configurable **fake `mk.NativePlayer` platform** (property get/set,
    observers, commands, configuration), because substantial production
    behaviour is gated on `player.platform is mk.NativePlayer` (subtitle
    visibility, network tuning, recording eligibility, auto-sync — 4838);
    tests choose native or non-native explicitly.
  - `FakeVideoController implements mkv.VideoController`: notifiers,
    completers and deliberate frame-readiness behaviour.
  - Controllable `ready` callbacks (never fired synchronously inside the
    factory, before the State's assignments finish), old-instance events
    after replacement.

  **Environment fixture** (existing overrides; no further application
  seams in phase 1):

  | Dependency | Handling |
  |---|---|
  | `PlayerDisplayControls` singleton (wakelock on load, play/pause writes, teardown — `player_display_controls.dart:9`) | plugin / platform-interface channel mocks, recorded |
  | window_manager / `SystemChrome` (fullscreen on Linux/Windows 1773, orientation, UI mode, teardown) | recorded channels; statements are never skipped |
  | PiP (guarded by real `dart:io Platform` predicates, 1706) | **device-pending** on the desktop harness; a narrowly reviewed platform-predicate seam may be proposed before the PiP phase, otherwise those branches are listed device-only and never claimed as covered |
  | Storage/profile (`ProfileRuntime.isProfileCommitted` throws uninitialized; policy guards on native recording eligibility 3443; subtitle/tracking/skip/completion/defaults loads in `initState`) | existing storage/profile test doubles initialized by the harness; for committed-profile native tests `ProfilePolicyGuard`'s active-profile mirror is initialized/reset explicitly (`profile_policy_guard.dart:19`), since `ProfileRuntime` alone leaves synchronous permission checks closed |
  | Files/HTTP (`getTemporaryDirectory` + HTTP client in addon subtitles 17648) | path_provider channel mock + HTTP override per test |
  | Timers/leases (analytics heartbeat in `initState`, autosave 3696, recovery timers, output lease release) | `fake_async`/explicit pumps, drained at teardown; no unrestricted `pumpAndSettle` |
- **(H2) Real libmpv in tests.** `/opt/homebrew/lib/libmpv.dylib` exists
  locally but not on CI/Linux runners; real decoding in widget tests is
  timing-dependent. Rejected as the primary harness; may supplement a
  smoke test locally.
- **(H3) Source-text characterization only.** Rejected: AGENTS says
  source-text tests are not behaviour tests.

The harness also provides a widget pump with the storage/service fakes, a
method-channel recorder, and helpers to drive TV keys, taps and timers.

**Per-phase profile/resource evidence** (AGENTS "Profiles, asynchronous
work, and resources"): each stateful phase's step 0 pins, where its
members participate, captured-scope writes, profile switch/deletion during
the operation, stale queued actions, route replacement, events from an old
player instance, and ordered teardown. Existing epochs, tickets and guards
stay intact; `mounted` forwarding alone is not evidence. Device-only
coverage stays pending until performed.

## Shared state that stays State-owned

Static occurrence counts at `ed728b078` (not resolved bindings, but
executable coupling): `_player` in 76 members, `_duration` 39,
`_activePlaylist` 30, `_currentIndex` 28, `_isTransitioning` 27.
`_openMedia` clears resume protection and begins engine generations
(4828); EOF combines trackers, completion, sleep, IPTV and episode routing
(5244); subtitle rollback joins engine diagnostics, persistence and menu
correction (5110). These groups **stay in the State** (reached through
Host forwarders) through every phase unless a phase section proves a
complete ownership transfer:

- player instance, readiness, instance/media generations, position/duration;
- current playlist/index/source/URL/headers and effective content identity;
- transition, validation and sleep-stop gates;
- resume guard/epoch (shared by open, renderer fallback and switching);
- IPTV current identity and switch ticket; navigation and scrub generations.

Each phase section lists every field it moves (with its readers/writers
from the analyzer binding scan) and every shared field its Host forwards.

## Phase map (risk- and dependency-ordered)

Line numbers at `ed728b078`; each phase section re-measures. "≈ out" is
declaration lines leaving the facade (facade growth from imports, Host
adapters and wiring is not subtracted). Phases over ~500 lines name
**several destination files** (each ≤ 500 preferred, ≤ 800 hard).
Integration milestones (**M**) run the full suite, both release builds and
a cross-phase scenario pass over the workflow before the next milestone
starts.

| Phase | Content | ≈ out | Risk |
|---|---|---|---|
| 1 | Format commit (a); Dart move checker + analyzer comparator; harness seam S + fakes + source reader; CI registration; top-level types + parameter-only helpers (frozen list in the phase-1 section) | 300 | low (moves) / **high (tooling + seam)** |
| 2 | Sleep timer (13826–13930) | 110 | low |
| 3 | Skip segments (1797–1819, 1871–2040) | 250 | med |
| 4 | Speed / aspect / orientation (13739–13825, 13931–14030 subset) | 230 | med |
| 5 | Trackers: Trakt/Simkl/MDBList scrobble + heartbeats, analytics heartbeat, tracker percent helpers (2041–2750) | 700 | med |
| 6 | Local completion (1820–1870, 10374–10478) | 160 | med |
| 7 | PiP + background/wakelock (11635–11882) — PiP branches device-pending unless a reviewed predicate seam | 250 | high |
| **M1** | integration gate: controls/tracker/lifecycle scenarios | | |
| 8 | Subtitle engine I: subtitle settings, sync overlay, auto-sync pill/notice (2940–3088 auto-sync part only, 6380–6626) | 450 | med |
| 9 | Subtitle engine II: apply + diagnostics + failure + rollback (5014–5200, `_SubtitleApplyAttempt` users) | 300 | high |
| 10 | Subtitle sources and preferences: restore, default audio/subtitle language, forced, addon fetch/auto-select, Stremio download, priority (17164–18044) | 880 | high |
| **M2** | subtitle integration gate: one state-ownership map for phases 8–10; apply/failure/persistence/audio-policy races | | |
| 11 | Identify title + subtitle search sheet (15932–16645) | 720 | med |
| 12 | Tracks sheet + unified player menu (16647–17162) | 520 | med |
| 13 | Resume: keys, restore, seek/verify/landing, enhanced state, save + write guard (12093–12905) | 810 | high |
| 14 | IPTV recording (7691–8297) | 610 | med |
| 15 | IPTV workflow (one milestone, separate collaborators, one switch/recovery owner): zap paging, guide categories, Start Over/catch-up, live retune, channel switch, live open, audio preference, stream error (759–1272 IPTV members, 6627–7690, 8298–8562) | 1,700 | highest |
| **M3** | IPTV integration gate | | |
| 16 | Startup: debrid direct, startup VOD, VOD failover, startup gate (8563–9200) | 640 | high |
| 17 | Source switching: source sheet, source playlist / Stremio / IPTV source switch (9201–9820) | 620 | high |
| **M4** | startup/source-switching integration gate | | |
| 18 | Stremio TV + Debrify TV channel navigation and banners (9821–10330, 13414–13570, 14124–14236) | 700 | high |
| 19 | Episode navigation: ended, next/previous, shuffle/random, series next, title/subtitle info (5210–6360, 10332–10373) | 1,200 | high |
| 20 | Playlist load/resolve, video metadata wait, PikPak retry, metadata preload/save (10479–11634) | 1,150 | high |
| 21 | Episode fetch + synthetic guide (14242–14736) | 500 | high |
| **M5** | episode navigation/load/fetch integration gate | | |
| 22 | Player engine I: audio/output lease/effects, passthrough, tvOS remedy/display match, decoder/renderer fallback (2750–3263 minus auto-sync, 4076–4692) | 1,100 | highest |
| 23 | Player engine II: `_initializePlayer`, open media, network tuning, instance subscriptions, startup watchdog (3264–4075, 4693–4978) | 1,350 | highest |
| 24 | Controls runtime: auto-hide, TV bar/scrub, TV keys, overlays, gestures (12907–13738) | 830 | high |
| 25 | `build` decision (D6), end-state exception, completion audit, CI structure job, device checklist | — | — |

The order puts self-contained features first and the shared engine last,
so early phases build the Host/adapter scaffolding on low-risk code.
Phase numbers after 2 are provisional; each phase section may split or
merge neighbours after its inventory, recorded in Progress.

## Phase 1 — format, tooling, harness seam, top-level types and parameter-only helpers

Branch `refactor/vplayer-p1` off `ed728b078`. Evidence
`refactor-evidence/vplayer/p1/`. The declaration moves are small; the risk
is the tooling and the seam, which every later phase depends on.

### Frozen move list

| Original | Kind | Destination | Name |
|---|---|---|---|
| `_ManualSourceValidationFailure` 167 | type | `models/vp_manual_source_validation_failure.dart` | `VpManualSourceValidationFailure` |
| `_SeasonEpisodeSelection` 171 | type | `models/vp_season_episode_selection.dart` | `VpSeasonEpisodeSelection` |
| `_SubtitleApplyAttempt` 178 | type (mutable; object identity and completion lifecycle preserved — documented legacy exception) | `models/vp_subtitle_apply_attempt.dart` | `VpSubtitleApplyAttempt` |
| `_IptvZapPage` 207 | type | `models/vp_iptv_zap_page.dart` | `VpIptvZapPage` |
| `IptvCatchupRequestGate` 229 | type | `models/iptv_catchup_request_gate.dart` | unchanged; **exact facade re-export** added beside the two existing exports (163) |
| `_RandomChoiceTile` 18046 | widget | `presentation/vp_random_choice_tile.dart` | private name kept; `typedef VpRandomChoiceTile = _RandomChoiceTile;` (spotlight/stremio precedent) |
| `_format` 13706 | instance, parameter-only | `application/vp_format.dart` | `vpFormatDuration` |
| `_pad2` 14262 | static (`static` removal declared) | same file | `vpPad2` |
| `_generateFilenameHash` 18036 | instance, parameter-only (algorithm frozen) | `application/vp_filename_hash.dart` | `vpFilenameHash` |
| `_normalisePosterUrl` 16036, `_normalisedContentType` 15977, `_identityMetaSubtitle` 16042, `_filterIdentitySearchResults` 16007, `_subtitleSearchDisplayLabel` 15991 | instance, parameter-only (imports `lib/models/stremio_addon.dart`) | `application/vp_identity_text.dart` | `vpNormalisePosterUrl`, `vpNormalisedContentType`, `vpIdentityMetaSubtitle`, `vpFilterIdentitySearchResults`, `vpSubtitleSearchDisplayLabel` |
| `_diagnosticSubtitleId` 5031, `_subtitlePreferenceMatchesAttempt` 18025 | both **static**, parameter-only (imports media_kit `SubtitleTrack` + `VpSubtitleApplyAttempt`); `static` removal declared | `application/vp_subtitle_identity.dart` | `vpDiagnosticSubtitleId`, `vpSubtitlePreferenceMatchesAttempt` |

Step 0 re-proves each helper parameter-only (no `this`, `widget`,
`context`, State field, service or I/O reference; analyzer binding scan)
and that its imports are allowed in `application/` (no Flutter UI; a
legacy DTO under `lib/screens/` needs an exact scoped compatibility import
or the helper goes to `presentation/`). A helper failing the proof is
dropped from phase 1 (recorded), never transformed. **Excluded** (not
parameter-only — they move with their owners): `_randomStartOffset`
(widget field + `_random`), `_percentStartOffset` (widget field),
`_dockGeometrySignature` (State fields + `MediaQueryData`).

### Steps

- **(a) Format-only commit** `style(vplayer): format the original video
  player screen` with the AST optional-comma proof (rule 2); if formatting
  grows the facade, its baseline is **raised explicitly** in
  `file_size_baseline.txt` with a dated note (`check_file_sizes.py
  --update` only lowers). R = (a).
- **Step T — tooling.** `check_dart_moves.py` (rule 2) with fixtures and
  every negative; all-`retained` self-compare of R; every existing Dart
  manifest self-test passes with an isolated `--parser-package`;
  `check_vplayer_analyzer.py` (rule 6); CI wiring (rule 7).
- **(S) Harness seam checkpoint** (H1): the three interception patches,
  test-mode-only installation, the source guard, the token proof; then the
  fakes, environment fixture and source reader.
- **Step 0 — characterization of the original (at S).** Harness smoke
  tests: the screen mounts with a fake player for a direct URL, a
  playlist, an IPTV channel list and a Stremio TV channel, opens media
  with the recorded configuration, and disposes cleanly with no pending
  timers. Phase-1 behaviour through original callers: manual-source
  rejection and rollback (`_ManualSourceValidationFailure`); season/episode
  validation, acceptance and cancellation in the identity sheet
  (`_SeasonEpisodeSelection`); a subtitle selection's apply-attempt
  lifecycle (success, failure rollback, persisted audio id); zap page
  offsets/totals through an IPTV zap; `IptvCatchupRequestGate` (reuse
  `iptv_channel_sheet_responsive_test.dart:292`, add completion/
  cancellation/stale cases); the random-playback menu tiles; each helper
  through a caller (duration text, recording file name hash, identity
  search labels/filtering, subtitle preference matching). The filename
  hash is the **fallback resume identity** (`_resumeIdForEntry` 12201), not
  a recording name (recordings use the timestamp function at 7997): a
  plain playlist entry without TorBox/PikPak identifiers, an existing
  fallback bookmark, asserted restored seek and storage identity,
  extension normalisation and the empty-title fallback to `widget.title`;
  a mutation of the hash helper must fail that test. Mutation proofs
  on S for every test; coverage matrix.
- **Claude sample** (≥ 75 %), **step 0b** if needed.
- **Step 1 — moves** per the frozen list; source-test retargets; theme
  path lists extended.
- **Gate** (commit message contains `gate`), **independent Codex review**,
  merge, merge checks, push.

### Phase 1 device checklist (end of series)

Random-playback menu tiles render and select on phone and TV; IPTV
catch-up/Start Over cancellation still wins over a slow lookup; identity
search labels unchanged; resume of a plain playlist entry (no TorBox/PikPak id) lands at the saved position after the update.

## Phase 2 — sleep timer (first collaborator; establishes the scaffolding)

Branch `refactor/vplayer-p2` off the phase-1 merge `31a347ad2`. Evidence
`refactor-evidence/vplayer/p2/`. Line numbers at `2eb4fda82` (same facade content as `31a347ad2`); re-measure
at the phase base.

Deliberately small: it is the first stateful phase, so it introduces the
series scaffolding that every later phase extends — the State constructor
body, `_vpSetState`, the first Host interface + private adapter, the
checker's `_host` forms in a real manifest — on low-risk code.

### Moves → `lib/features/video_player/presentation/legacy_video_player/vp_sleep_timer_controller.dart`

`class VpSleepTimerController` + `abstract interface class VpSleepTimerHost`
(same file, ≈ 150 lines).

| Original | Kind | Fate |
|---|---|---|
| `_sleepTimerMode` 1454 (+ the 4-line section comment 1450–1453, which moves with it) | field, init `SleepTimerMode.off` | moved → `sleepTimerMode` |
| `_sleepTimerDeadline` 1459 (doc) | field, `null` | moved → `sleepTimerDeadline` |
| `_sleepTimerArmedMinutes` 1463 (doc) | field, `0` | moved → `sleepTimerArmedMinutes` |
| `_sleepTimer` 1464 | field, `null` | moved → `sleepTimer` |
| `_sleepTimerMinutesLeft` 13813 | getter | moved → `sleepTimerMinutesLeft` |
| `_sleepTimerButtonLabel` 13824 | getter | moved → `sleepTimerButtonLabel` |
| `_showSleepTimerSheet` 13830 | method | moved → `showSleepTimerSheet` |
| `_applySleepTimerSelection` 13851 | method | moved → `applySleepTimerSelection` |
| `_startSleepCountdown` 13865 | method | moved → `startSleepCountdown` |
| `_cancelSleepTimer` 13877 | method | moved → `cancelSleepTimer` |
| `_fireSleepTimer` 13896 | method | moved → `fireSleepTimer` |
| `_showSleepTimerToast` 13906 | method | moved → `showSleepTimerToast` |

All four field initializers are literals/`null` — **inert** (recorded
proof). Their relocation from State slots 1454–1464 to the constructor
body is unobservable. Dispose keeps its direct cancel-and-clear statements
(`_sleep.sleepTimer?.cancel(); _sleep.sleepTimer = null;`) — replacing them
with `cancelSleepTimer()` would add a mode change and possibly `setState`
during teardown.

**Stays State-owned** (shared-state rule): `_sleepStopLatched` (1470; read
by recovery 690, decoder replacement 4321, EOF 5245, episode navigation
5790/6212, playlist load 10574, resume-from-background 11828, play toggle
13703, episode request eligibility 14317),
`_activeMediaShouldPlay`, `_playerCreated`, `_player`, `_hideTimer`,
`_currentIptvChannel`, `_saveResume`, `_scheduleAutoHide`,
`_openPlayerMenuQuick`.

**Host** `VpSleepTimerHost` (exact 12 members; every one used —
`sleepStopLatched`/`activeMediaShouldPlay` are correctly setter-only; computed
forwarders in `_VpSleepTimerHostAdapter` in the facade library):
`bool get mounted`, `BuildContext get context`,
`void setState(VoidCallback fn)` (→ `_s._vpSetState`),
`void openPlayerMenuQuick(PlayerMenuSection section)`,
`Timer? get hideTimer`, `IptvChannel? get currentIptvChannel`,
`void scheduleAutoHide()`, `set sleepStopLatched(bool v)`,
`set activeMediaShouldPlay(bool v)`, `bool get playerCreated`,
`Future<void> saveResume()` (narrow no-argument forwarder to
`_s._saveResume()`; its optional parameters default to `false`/`null`,
12671), `mk.Player get player`. Destination imports (frozen): `dart:async`,
Flutter material, media_kit as `mk`, `IptvChannel`
(`models/iptv_playlist.dart`), `PlayerMenuSection` + `kUnifiedPlayerMenuEnabled`
(`player_menu_panel.dart`), `SleepTimerMode` + `SleepTimerSelection` +
`SleepTimerSheet` (`sleep_timer_sheet.dart`) — constants and the sheet are
imports, not Host members.
Declared receiver substitutions inside moved bodies (by occurrence):
`mounted`→`_host.mounted` (3), `context`→`_host.context` (2),
`setState(`→`_host.setState(` (3), `_openPlayerMenuQuick`,
`_hideTimer`, `_currentIptvChannel`, `_scheduleAutoHide`,
`_sleepStopLatched`, `_activeMediaShouldPlay`, `_playerCreated`,
`_saveResume`, `_player` → their `_host.` forms; moved-member references
lose their underscore (renames). The exact return type of
`_saveResume` and the `context` uses (`SleepTimerSheet.show(context, …)`,
`ScaffoldMessenger.of(context)`) are verified at step T; no builder-local
`context` exists in the moved code (checked).

**Retained code — declared substitutions** (`_sleep` = the controller
field): 691 and 5243 `_sleepTimerMode` → `_sleep.sleepTimerMode`;
5244 `_cancelSleepTimer()` → `_sleep.cancelSleepTimer()`; 5247
`_showSleepTimerToast(` → `_sleep.showSleepTimerToast(`; `dispose`
11878–11879 `_sleepTimer` → `_sleep.sleepTimer` (same statement
position); 13138/13139 and 15476/15477 tear-offs
`_showSleepTimerSheet` → `_sleep.showSleepTimerSheet`,
`_sleepTimerButtonLabel` → `_sleep.sleepTimerButtonLabel`; 17070–17074
menu arguments → `_sleep.` forms (`onSleepSelected:
_sleep.applySleepTimerSelection` — tear-off identity is not compared by
the menu; verified at step 0).

**New scaffolding (frozen):** `late final VpSleepTimerController _sleep;`
(declared at the old field slot 1454), the State constructor
`_VideoPlayerScreenState() { _sleep = VpSleepTimerController(_VpSleepTimerHostAdapter(this)); }`,
`void _vpSetState(VoidCallback fn) => setState(fn);`, the adapter class
after the State class. Constructor of the controller only stores the
host. Frozen fields: `final VpSleepTimerHost _host;` in the controller and
`final _VideoPlayerScreenState _s;` in the adapter.

### Step T (phase 2)

- Materialize the **complete phase-2 manifest** and make it compare:
  the four controller-owned fields, constructor, adapter, nullable chains
  (`sleepTimer?.cancel()`), the `Timer(duration, fireSleepTimer)` tear-off
  and the getter interpolation (`'$sleepTimerMinutesLeft min'`). The
  phase-1 fixture only exercises retained State fields through the Host;
  the binding guard (`occurrence_field_bindings.py:257`, `:302`) currently
  rejects bare renamed references. Add **owner-scoped bare access**: a
  moved field may be referenced bare only inside its declared owning
  controller class, keeping lexical-binding checks and mandatory
  qualification everywhere else (never disabled globally); negatives —
  bare access from another class, a same-named local capturing the field,
  and an owned field referenced through `_host`. `this.` qualification is
  not used (the checker rejects `this` in moved State bodies, 186).
- **CI transition** in the production creation commit: the current-tree
  check and self-test switch to `vplayer_p2.json`; P1 stays checked with
  `--at 31a347ad2`; the analyzer step selects the P2 manifest/inventory
  while preserving P1's diagnostic mappings; new characterization files
  join `ci_behavior_tests.txt`.
- **Source-test retarget:** `test/player_auto_next_routing_test.dart:29`
  searches `_sleepTimerMode == SleepTimerMode.endOfItem` without asserting
  it exists, so after qualification `indexOf` would return −1 and the
  ordering comparison would still pass. Retarget to
  `_sleep.sleepTimerMode == SleepTimerMode.endOfItem` through validated
  current source, **assert the anchor is non-negative** before comparing,
  and prove a removed or reordered sleep branch fails.

### Step 0 — characterization of the original

Through the harness (fake player, `fake_async`): countdown arm → label
"N min" (ceil of the real remaining time; **minute-by-minute decrement is
recorded device-pending**: both the deadline and the remaining-time read use
real `DateTime.now()` (13818, 13870), which `FakeAsync` does not intercept,
and a clock seam would need its own proof on the original — not added),
deadline expiry → `_saveResume` before
`pause`, toast texts, latch set (next auto-advance suppressed);
end-of-item → EOF stops with "Sleep timer — stopping here" and no
advance; off → toast + label null; re-arming cancels the old timer;
dispose with an armed countdown → no fire after dispose; **dispose (and
player replacement) while `_fireSleepTimer` is suspended in `_saveResume`**,
then release the save — pin the calls, errors and toast behaviour (any
existing defect recorded in Follow-ups, not fixed); the latch against an
**already queued automatic advance** and a **live recovery attempt**; a live IPTV
channel → `allowEndOfItem` false (legacy sheet path is dead behind
`kUnifiedPlayerMenuEnabled` — record as dead, like c18); the unified menu
receives mode/armed/minutes-left and its selection callback applies;
the controls dock label. Mutation proofs on the original; coverage
matrix; Claude sample.

### Device checklist (end of series)

Sleep timer 15 min countdown on phone + Android TV (Flutter player) +
tvOS + desktop: label counts down, pauses at expiry, position saved,
next episode does not start; "end of episode" stops at EOF.
After sleep stop, check Android renderer replacement during a suspended resume
save and Android/iOS Start Over/background playback intent; the intent write
remains device-pending (`e14`), while the sleep latch must prevent auto-resume.

## Phase 3 — skip segments

Branch `refactor/vplayer-p3` off the phase-2 merge `fc24e32ae`. Evidence
`refactor-evidence/vplayer/p3/`. Line numbers at `7775198f5` (phase-2
gate); re-measure at the phase base by name.

### Moves → `presentation/legacy_video_player/vp_skip_segment_controller.dart`

`class VpSkipSegmentController` + `abstract interface class VpSkipSegmentHost`
(≈ 260 lines).

| Original | Kind | Fate |
|---|---|---|
| comment 1282–1284 + `_skipSegmentSettingsLoaded` 1285 | field `false` | moved → `skipSegmentSettingsLoaded` |
| `_skipSegmentsEnabled` 1286 | field `false` | moved |
| `_skipSegmentProviderId` 1287 | field `SkipSegmentProviders.auto` (a `static const` String — verify) | moved |
| `_skipSegmentProvider` 1288 | field `null` | moved |
| `_skipSegments` 1289 | field `SkipSegments.empty` (const — verify) | moved |
| `_loadedSkipSegmentsKey` 1290, `_loadingSkipSegmentsKey` 1291 | fields `null` | moved |
| `_skipSegmentsFetchGeneration` 1292 | field `0` | moved |
| `_skipSegmentsCache` 1293 | `final` map literal | moved |
| `_skipSegmentsMediaReady` 1304 (doc) | field `true` | moved |
| `_loadSkipSegmentSettings` 1714 | method | moved |
| `_currentSkipSegmentRequest` 1789 | method (record return type) | moved |
| `_syncSkipSegmentsForCurrentContent` 1854 | method | moved |
| `_resetSkipSegmentState` 1923 | method | moved |
| `_activeSkipSegment` 1932 | getter | moved |
| `_syncActiveSkipSegmentUi` 1938 | method | moved |
| `_skipActiveSegment` 1942 | method | moved |

Relocation changes initializer timing (State slots 1285–1304 → State
constructor body); every initializer above is a literal, a `static const`
(`SkipSegmentProviders.auto`, `SkipSegments.empty` — confirmed) or an empty
map literal; recorded proof per field. **`_activeSkipSegmentUi` (1394)
stays State-owned**: its `SkipSegmentUiController()` → `ValueNotifier(null)`
constructor dispatches a debug memory-allocation event
(`change_notifier.dart:544`, `:235`), so moving the allocation would change
that event's order relative to later notifier allocations (1433). The
controller reaches the same instance through the Host.

**Stays State-owned:** `_isTransitioning`, `_duration`, `_position`,
`_playbackUiClock`, `_player`, `_playerCreated`, effective content
identity getters, `_seriesPlaylist`, `_findSeriesEpisodeForCurrentIndex`,
`_traktSeasonEpisode`, the tracker seek methods (phase 5 re-points them),
`_activeSkipSegmentUi` (see above),
`_skipButtonBottom` (dock layout, not skip logic).

**Host** `VpSkipSegmentHost` (exact, every member used; 19 names / 20
declarations, signatures frozen): `bool get mounted`,
`void setState(VoidCallback fn)` (→ `_vpSetState`),
`String? get effectiveContentImdbId`, `String? get effectiveContentType`,
`int? get effectiveContentSeason`, `int? get effectiveContentEpisode`,
`bool get isTransitioning`, `Duration get duration`,
`Duration get position` + `set position(Duration v)`,
`SeriesPlaylist? get seriesPlaylist`,
`SeriesEpisode? findSeriesEpisodeForCurrentIndex(SeriesPlaylist sp)`,
`({int? season, int? episode}) traktSeasonEpisode()` (non-null outer
record), `bool get playerCreated`,
`PlaybackUiClockController get playbackUiClock`, `mk.Player get player`,
`SkipSegmentUiController get activeSkipSegmentUi`, and
`void traktScrobbleSeek(Duration)`, `void simklScrobbleSeek(Duration)`,
`void mdblistScrobbleSeek(Duration)` (exact types verified at step T).
The moved request method keeps its nullable five-field named-record return
type (1788). Destination imports (frozen at step T): `dart:async`, Flutter
foundation/services, media_kit, custom series identity, series playlist,
skip segment service + storage, playback UI clock, skip segment UI
controller. `HapticFeedback`, `SkipSegmentsStorage`,
`SkipSegmentProviders`, `CustomSeriesIdentity`, `RegExp` are imports.
`debugPrint` stays a top-level call.

**Retained substitutions** (`_skip` = controller): `initState` 1668
`_loadSkipSegmentSettings()` → `_skip.loadSkipSegmentSettings()`; player
subscriptions 3815/3816/3861–3863 (`_skipSegmentsMediaReady = true` →
`_skip.skipSegmentsMediaReady = true`, sync calls → `_skip.`); 4665
`_activeSkipSegmentUi.clear()` stays as is (State-owned); playlist load
10459 and 10651; dispose 11954–11956 (generation bump and provider close
**in place**, each statement individually, not via a new method); 11998
`_activeSkipSegmentUi.dispose()` unchanged; TV key handler 13315/13316; build 15527 (`valueListenable:`)
and 15560 (`onPressed: _skip.skipActiveSegment` — tear-off;
`SkipSegmentButton` is stateless and the dock compares geometry, not
callbacks — confirmed). 15527 `valueListenable: _activeSkipSegmentUi`
unchanged.

**Scaffolding:** the existing State constructor is now a **patched**
declaration (keeps the `_sleep` assignment, appends the `_skip` one);
`late final VpSkipSegmentController _skip;` at the old slot 1285;
`_VpSkipSegmentHostAdapter` after the State class.

**Step T / CI transition:** materialize the complete P3 manifest before
moving code (owned fields, map subscripts, nullable record selectors,
interpolation, generation increments, the Host position write); switch
both current/self-test move commands (`checks.yml:77`) to P3, keep P1
`--at 31a347ad2` and add P2 `--at fc24e32ae`; switch **both** the analyzer
manifest and inventory (`checks.yml:95`; historical mappings compose via
`check_vplayer_analyzer.py:45`); history protection covers the ten P1
files plus the sleep controller; register the new tests and extend the
three theme lists (`theme_surface_manifest.txt:26`,
`theme_rendered_set.py:68`, `source_guard_test.dart:50`).

### Step 0 — characterization of the original

Settings load (enabled/disabled, unavailable stored provider → auto,
provider closed/replaced); request gating (custom identity, settings not
loaded, disabled, media not ready after a playlist switch, transitioning,
zero duration, non-series, invalid/fallback IMDb id via the series
playlist, season/episode from the playlist, from the effective content,
from the Trakt parse, negative season/episode < 1) and the exact key
(provider:imdb:season:episode:seconds); fetch: cache hit, in-flight
dedupe by key, generation/stale-request rejection when the key changes
mid-fetch, profile switch or dispose during the fetch, error → cached
empty + debug log; UI: button appears only inside a segment of the
loaded key, skip seeks to `min(end, duration)`, updates the clock
immediately, tracker seeks in order, haptic; TV key path; reset on
playlist switch; dispose closes the provider. Fake provider transport: **no application seam** —
`SkipSegmentProviders.create` builds `http.Client()` internally, which
reaches the harness's existing `VideoPlayerHttp` `MockClient` override
(`video_player_environment.dart:83`, `:189`); held replies/errors and a
test-only client-close trace drive the races (close-aborted requests and
late replies surviving close). Use a stored single-provider choice to
reach the facade's error handler (auto swallows child errors,
`skip_segment_service.dart:148`). **Classified:** provider replacement in
`_loadSkipSegmentSettings` is dormant (only caller is `initState`, provider
initially null); the unavailable-provider branch is web-only (storage
normalises unknown ids, `skip_segments_storage.dart:37`) → web-pending.

**Races and boundaries (pin existing behaviour, defects included, never
corrected):** held A→B→A requests releasing the older A first, then a
position tick — success and error (the handlers write the cache before the
generation/mounted check, and `whenComplete` clears loading by key alone,
1885/1898/1911); the engine media-boundary clear (4665) independently of
the playlist reset; the failed-load re-arm (10459) with no incoming
duration event. **Profile:** the original guards are `mounted`,
generation and request key only — no profile/session identity (1719,
1844, 1886); characterize separately (a) completion while the outgoing
route is still mounted during the picker's exit animation
(`profile_gate.dart:360`), (b) completion after disposal, (c) an incoming
route with a different profile's enabled/provider settings. Pin the actual
outcomes; any profile-isolation gap goes to Follow-ups, unchanged by the
move. Mutation
proofs, coverage matrix, Claude sample.

### Device checklist (end of series)

Skip intro / Skip credits button on a series with segments (phone, Android TV
Flutter player, tvOS, desktop): appears, skips to the segment end, TV
Select skips; switching episode does not flash the button.

## Phase 4 — playback speed, aspect mode and orientation

Branch `refactor/vplayer-p4` off the phase-3 merge `890df14d8`. Evidence
`refactor-evidence/vplayer/p4/`. Line numbers at `d6e91c62a` (phase-3
gate); re-measure at the phase base by name.

### Moves → `presentation/legacy_video_player/vp_display_mode_controller.dart`

`class VpDisplayModeController` + `abstract interface class VpDisplayModeHost`
(≈ 290 lines).

| Original | Kind | Fate |
|---|---|---|
| `// Aspect / speed` comment + `_aspectMode` 1433 | field `AspectMode.contain` (enum const) | moved → `aspectMode` |
| `_playbackSpeed` 1434 | field `1.0` | moved → `playbackSpeed` |
| `// Press-and-hold…` comment + `_speedBeforeHold` 1444 | field `null` | moved → `speedBeforeHold` |
| `_landscapeLocked` 1448 | field `false` | moved → `landscapeLocked` |
| `_applyAspectVideoZoom` 2808 | method | moved |
| `_cycleAspectMode` 13503 | method | moved |
| `_changeSpeed` 13588 | method | moved |
| `_onSpeedButton` 13600, `_onAspectButton` 13608 | methods | moved |
| `_setPlaybackSpeed` 13616, `_setAspectModeDirect` 13622 | methods | moved |
| `_onLongPressStart` 13629, `_onLongPressEnd` 13659 | methods | moved |
| `_toggleOrientation` 13669 | method | moved |
| `_currentFit` 13687, `_getCustomAspectRatio` 13894 | methods | moved |

All four initializers are literals/enum constants → inert (recorded).
**Stay State-owned:** the `_aspectRatioHud` (1429) and `_speedHoldHud`
(1445) `ValueNotifier`s (allocation-event order, phase-3 rule), reached
through the Host; `_buildCustomAspectRatioVideo` (a build helper reading
subtitle settings and the video controller; its calls to the two moved
getters become `_display.` substitutions); `_controlsVisible`,
`_isPlaying`, `_dockBand`, `_player`, `_saveResume`, `_scheduleAutoHide`,
`_openPlayerMenuQuick`.

**Host** `VpDisplayModeHost` (exact; verified at step T): `mounted`,
`context` (State context — `_onLongPressStart` uses
`context.findRenderObject()`; no builder-local context in the moved
bodies), `setState` (→ `_vpSetState`), `mk.Player get player`,
`void scheduleAutoHide()`, `Future<void> saveResume()` (the moved bodies
call it unawaited exactly as the original), `void
openPlayerMenuQuick(PlayerMenuSection)`, `ValueNotifier<AspectRatioHudState?>
get aspectRatioHud`, `ValueNotifier<bool> get speedHoldHud`, `bool get
isPlaying`, `ValueNotifier<bool> get controlsVisible` (verify type),
`double dockBand(double base)` (verify signature), `bool get
hideBackButton`, `bool get hideOptions` (the two `widget.` reads — live
forwarders to `_s.widget.…`, read at the original moment). These
`widget.hideOptions` → `_host.hideOptions` substitutions are a new shape
(the widget guard recognises `_deps` *invocations*,
`occurrence_field_bindings.py:289`, `check_settings_moves.py:417`): step T
registers both complete selector substitutions in the real P4 manifest via
`registered_occurrence_substitutions.py:17` (or a narrowly scoped
extension), freezes the adapter bodies `_s.widget.hideBackButton` /
`_s.widget.hideOptions`, adds rejection cases for a cached widget value and
an altered lexical binding, and proves the complete P4 manifest before
extraction. All 14 Host members have readers; `_controlsVisible` is
`ValueNotifier<bool>`; `_dockBand(double legacy)` returns `double`. Imports:
`dart:async`, `dart:math` as `math`, Flutter material + services,
media_kit, `AspectModeUtils`/`AspectMode`, `AspectRatioHudState`,
`PlayerMenuSection` + `kUnifiedPlayerMenuEnabled`.

**Retained substitutions** (33 references on 32 lines, measured by the
design review; retained resume/defaults assignments stay **direct field
writes** `_display.playbackSpeed = …`, never routed through the action
methods, which would add effects):
`initState` 1657/1659 (`_landscapeLocked` writes/read), player creation
2656 (`_applyAspectVideoZoom()`), player defaults 6208/6264 (aspect write
+ debug log read), PiP 11504, resume restore 12090–12093 (speed/aspect
writes + zoom), resume save 12511/12514 (reads incl. `_speedBeforeHold
?? _playbackSpeed`), controls dock 12914–12919, the TV/keyboard cycle at
14486, `_buildCustomAspectRatioVideo` 13722 (`_getCustomAspectRatio()`) and 13723 (`_currentFit()`) + build 14751/14760,
gestures 15013/15014 (`onLongPressStart: _display.onLongPressStart` —
tear-offs; verify the gesture detector does not compare callback
identity across rebuilds in a way that changes recognizer state), styled
dock 15145–15152, unified menu 16737–16740. Resume code keeps reading
and writing these values at the same statement positions (shared-state
rule: the values move with their only state owner, the controller;
resume sees them through `_display.`).

**Scaffolding:** patched State constructor (keeps `_sleep`, `_skip`,
appends `_display`); `late final VpDisplayModeController _display;` at
slot 1433; `_VpDisplayModeHostAdapter`. CI: current → P4; P1 `--at 31a347ad2`, P2 `--at fc24e32ae`, P3 `--at 890df14d8`; earlier
`--at` their merges; analyzer manifest + inventory → P4.

### Step 0 — characterization of the original

Aspect cycle order through all 11 modes with HUD label/icon and its
1.5 s auto-clear (and no clear after dispose); `video-zoom` property per
mode on a native platform, skipped on a non-native one, failure logged;
speed cycle order and wrap, `setRate` calls, persistence via resume save
(including the held 2× not persisted: `_speedBeforeHold ?? speed`);
unified-menu speed/aspect selection, the no-op on the same aspect;
long-press 2× gating (locked controls, paused, edge guard, visible
controls top/bottom bars) and release restoring the prior speed, release
after dispose; orientation toggle (both directions, immersive mode,
`setState` only when mounted) via the method-channel recorder; resume
restore applying speed + aspect + zoom; player defaults setting aspect;
landscape lock seeded from `startsInPortrait`; PiP's read of the lock.
Legacy cycle paths behind `kUnifiedPlayerMenuEnabled` recorded dead —
`_changeSpeed` is **wholly dormant** (its only caller is the disabled
branch, 13605); aspect cycling stays live through key A (14486).
**Rendered aspect contract:** through the eleven-mode cycle assert the
rendered `mkv.Video.fit`, the custom-ratio branch and the numeric
`AspectRatio.aspectRatio` (13722/14751), not only HUD/zoom; native zoom
`0.000000`, cinema zoom `0.415037`. **Resume sampling:** suspend an
existing resume write (the preference transport barrier,
`sleep_timer_driver.dart:55`), queue another save, change speed/aspect or
start/end a hold, release, and assert the stored records (values are read
inside `_saveResumeLocked`, 12511, not at action time); saved speed `1.0`
skips both `setRate` and the assignment (12088). **Orientation async:** a
suspended orientation request completed after disposal, overlapping
toggles (both read the same initial lock), a rejected channel request —
record channel arguments/order and the `_scheduleAutoHide` timer creation
and draining (12673); preserve outcomes. One real pointer hold spanning a
rebuild pins long-press delivery (tear-offs of the same instance compare
equal; recognizers are reused by type). **Reachability:** the landscape
seed is desktop-covered; the phone-only portrait seed (`PlatformUtil:92`
uses real `dart:io Platform`) and PiP restore are device-pending.
Mutation proofs, coverage matrix, Claude sample.

### Device checklist (end of series)

Aspect modes visibly change framing on phone/TV/desktop/tvOS (incl.
cinema zoom); speed menu changes rate and persists on resume;
long-press 2× on phone; orientation toggle on phone; portrait-start seed
and PiP restore of the lock on phone.

## Follow-ups

- **Service/data ownership exit** (D1): data contracts for resume,
  trackers, subtitles, sources and IPTV replace the bridge's direct service,
  storage, channel and player calls.
- **`build` decomposition** (D6 exit): behaviour-level split into layout
  widgets with goldens, its own goal.

- **Video player Riverpod migration** (D1 exit): controllers become
  per-session/profile notifiers, one per batch, behaviour-tested; requires
  this series' collaborators and characterization tests.
- `lib/screens/video_player/**` oversized files (`iptv_channel_sheet` 3,667,
  `tracks_sheet` 2,197, `player_menu_panel` 1,844, …) — their own goal.
- Localization of player strings.
- Overlapping EOF callbacks suspended in completion storage can resume after
  disposal: the first clears end mode and the second enters the legacy
  next-episode lookup. Phase-2 characterization records the diagnostic and
  forbids silently fixing this disposed-screen work during extraction.
- Sleep expiry released after disposal still calls the disposed native player
  after saving. A rejection propagates; a successful late pause suppresses its
  toast. Phase-2 original characterization preserves this ordering defect.
- A live recovery open already issued before sleep pause can complete playing
  afterward under a delayed-open fake contract. The latch prevents subsequent
  recovery attempts; verify the real native behavior before a separate fix.
- Skip fetches have no profile/session guard: an outgoing route still mounted
  during profile handoff can publish its held result. Disposal rejects it;
  an incoming route independently reads its own settings. Phase-3 tests pin
  these three outcomes; add profile isolation only in a separate change.
- An older A→B→A skip completion writes the session cache before checking
  generation and clears loading by key alone. It can expose stale data on a
  tick or poison a later cache return while newer displayed data stays intact.
  Both success and error outcomes are preserved by Phase-3 characterization.
- Shortening duration within the same whole-second skip key can clamp a skip
  seek below the cached segment end and leave its button visible. Phase-3
  characterization records this existing result without changing it.


## Progress

2026-10-11 — **(a) and Step T complete; stop before S.**

- **R = `a43f44cbb33a05830bbcb0325c98a768d10cc166`.** Ran `dart format`
  on the original facade only. `vplayer_format_proof.py` records 18 inserted,
  zero deleted AST-optional commas, identical remaining scanner tokens/comments/
  literals, idempotence and rejected comment/literal/singleton-record mutations.
  Explicit dated baseline raise: 18,106 → 18,187 lines. Root player diagnostics
  rose 70 → 73: three formatting-induced `curly_braces_in_flow_control_structures`
  infos, recorded by declaration in `format-diagnostics.json`.
- **T = `c3b7dec1ae018ebdf51e2cdd77c19badf20b24bb`.**
  `check_dart_moves.py --self-test --self-compare-original`: all real-config,
  rule-2/round-2 negatives and historical fixtures pass; R has 893 exhaustive
  spans, zero differences. Current-tree and `--at c3b7dec1a` checks pass.
  All 26 existing Dart manifest self-tests and the Kotlin Phase-19 checker
  self-test pass. Accepted manifest runs use isolated `--parser-package`
  paths under `.dart_tool/vplayer_parser/`, with copied `*.dill` removed;
  heavy processes use `nice -n 19`. The 16-move/10-destination Phase-1 manifest
  is **draft**; its formatted evidence-only materialization also compares
  exactly and has zero analyzer errors. No production file was created.
- **Analyzer/checks.** `check_vplayer_analyzer.py` passes for root R/current
  (73), byte-identical strict R (133), rename probe (141), and `--at T`.
  Inventory includes infos and multiplicity: maxima across 33 identities.
  `flutter analyze` retains exactly R's 1,753 root diagnostics (exit 1);
  format, `check_file_sizes.py`, `check_search_architecture.py`, Python compile
  and diff checks pass. CI remains disabled until the **Step-1 commit creating
  the first `lib/features/video_player/**` file**; required wiring is listed
  in `dev/tool/dart_moves/README.md`.
- **Suite/deviations.** Completed original full suite via `suite_evidence.py`:
  12,793 successes, 14 failures, 28 errors, 20 skips. Focused post-T run:
  133 successes, one observed-baseline PiP source-assertion failure; comparison
  has no new failures, missing tests or new skips. Initial suite run with
  embedded parser paths outside the isolated root was stopped and replaced
  using an evidence-only routing wrapper; the initial focused run naming a
  nonexistent test was discarded. Formatting split one startup source guard;
  T's existing assertion now pins its complete expression with whitespace-
  tolerant matching, preserving the anchor and strengthening the assertion.
  Analyzer setup experiments are excluded from the inventory. All evidence
  and exact commands/notes are under
  `<git-common-dir>/refactor-evidence/vplayer/p1/`. Application/dependency
  files are unchanged after R. S, characterization, production moves and gate
  suite/builds remain unstarted.


### 2026-10-11 — S and Step 0 (complete; stop before moves)

- **Revisions.** S `80839d827383b05078178f292b56efbddd166fb1` is the
  separately committed characterization checkpoint; Step 0 is
  `c502380169cbc3a1394782c52a0fac08d7595e67`. Application code remains
  byte-identical to S; dependencies are unchanged and the Phase-1 move
  manifest stays draft. S's dated size exception is 18,251 lines.
- **S proof.** `vplayer_seam_proof.py --self-test`, the seam move-checker
  self-test and `check_dart_moves.py --manifest vplayer_p1_seam.json --at S`
  pass: two patched declarations, three exact interceptions, frozen hook
  scaffold, once-only defaults/configurations and ordered assignments.
  Installer/source guard passes both with and without the test flag. The
  harness flag is in the test command list and CI behaviour command.
- **Characterization.** Four original launch smoke cases and phase-1
  source rejection/rollback, identity validation/cancel, subtitle lifecycle,
  zap offsets/totals, catch-up ownership, active shuffle and fallback hash
  resume/storage scenarios pass. The full suite passes all 26 additions.
  All 10 helpers pass the analyzer binding/import proof; the unchanged
  strict-feature top-level rename probe from T remains valid. The current
  source reader validates ownership/body/history and chains relocation.
  Coverage and mutation tables are in the deps report. The legacy
  `_RandomChoiceTile` is dead under shared rule 4. **Step-0b correction:**
  the initial `_format` dead-code claim missed its `SeekHud` tear-off; the
  added HUD behavior test now covers it. Active duration/shuffle callers
  are also tested. PiP stays
  device-pending. No predicate seam or manufactured caller was added.
- **Mutations.** Detached original-S control: 26/26 pass. One application
  mutation per test plus six identity/total-boundary mutations: 32/32
  assertion kills. Original S is restored after each run. An offset-zero
  mutation that caused a microtask loop was interrupted/excluded and
  replaced by a total-boundary mutation; no assertion was weakened.
- **Suite/NOTE.** `suite_evidence.py run vplayer/p1/step0-suite-isolated
  --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`, then `compare --against
  original-suite-routed.jsonl`: **PASS**, 12,820 successes, 13 failures,
  28 errors, 20 skips; 26 added successful identities, zero new failures,
  missing tests or new skips. The profile-editor extra failure was a
  deterministic parser-path setup incompatibility; unchanged-source/test
  isolated 3x reruns and the final full run pass. No observed behavior
  flake/regression and no allowlist entry. The 41 remaining failures/errors
  match the observed original set after that environment repair.
- **Checks/evidence.** Root `flutter analyze --no-pub` retains S's 73 scoped
  identities with zero additions; the new harness folder analyzes cleanly.
  Final root analysis has exactly T's 1,753 diagnostic identities/counts
  (exit 1 for existing diagnostics); temporary earlier scan differences
  from vendor/test/build assets are archived separately.
  Sizes (2,984 files/140 ratchets), architecture (1,652), formatting, Python
  compile and diff checks pass. Heavy commands use `nice -n 19`; Flutter
  suite runs are serialized. All artifacts and exact commands are under
  `<git-common-dir>/refactor-evidence/vplayer/p1/`, including the named
  JSONL runs, `COMMANDS-step0.txt`, baseline delta and routing audit.
- **Routing/deferred work.** An evidence-only Python routing wrapper now
  covers outer CLI packages and nested hard-coded parser guards, including
  child tools; each invocation copies a fresh package under
  `.dart_tool/vplayer_parser/` and deletes copied kernels. Incomplete runs
  before lint cleanup/nested routing are excluded with NOTEs. Existing
  comparison code/manifests are unchanged. No production file, dependency
  change, bug fix, push, merge, branch switch or device command. Feature
  move/import/analyzer CI enables only in Step 1's first
  `lib/features/video_player/models/` production-file commit. Claude's
  independent mutation sample, any step 0b and production moves remain
  subsequent work.

### 2026-10-11 — Step 0b (complete; stop before moves)

- **Revision.** `849d3b343c4d13d8db96cae2070f479317489b2c`; 31 added
  behavior identities through original callers. Complete detached-original
  control at c50238016 passes 57/57; application/dependencies stay identical
  to S. The coverage matrix and mutation tables are in
  [the deps report](video-player-screen-deps.md).
- **Systematic sweep.** All 16 frozen declarations, 248 nested AST sites;
  113 valid mutations give 107 assertion kills and six proved equivalents.
  Every new test has its own assertion-failing original mutation witness.
  `build_evidence.py --require-complete` and `audit_mutations.py` pass; no
  unresolved site or surviving non-equivalent behavior is recorded.
- **Requested sample.** `run_sample.py` reruns all 20, with uniquely scoped
  c1: 18/20 assertion kills (90%). c15 is equivalent by the active-ticket
  invariant; c18 is unreachable after the const-true unified-menu return.
  c16 is refuted by public ticket values 1→3 versus mutant 1→2. The earlier
  `_format` dead-code claim missed its SeekHud tear-off; a new mounted pan/HUD
  behavior test kills c19 and systematic f01 without changing production.
- **Suite baseline.** `suite_evidence.py run vplayer/p1/step0b-suite --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true`, then `compare --against
  step0-suite-isolated.jsonl`: **PASS**. 12,851 successes, 13 failures,
  28 errors, 20 skips; exactly 31 additions and zero changed existing
  outcomes, new failures, missing tests or new skips. SDK/tree checks pass;
  the profile-editor test passes and no allowlist changes.
- **Checks.** Root analysis retains all 1,753 prior diagnostic identities;
  scoped analysis retains 73 S identities with zero additions. Harness
  analysis/formatting, current/`--at S` seam proofs, size, architecture and
  diff checks pass. The full-suite routing audit records 114 unique isolated
  parser packages, 342 copied kernels deleted and 618 nested redirects.
- **Evidence/deviations.** Artifacts and commands are under
  `<git-common-dir>/refactor-evidence/vplayer/p1/step0b/`; the observed suite
  baseline/delta are `step0b-baseline-outcomes.json` and
  `step0b-baseline-delta.json`. Invalid s07 compilation and the s17 paging
  loop are excluded with NOTEs; corrected s07 and the identical s17 patch
  against the unchanged underreported-total test assertion-fail. Flutter
  assertion-print classification and the `_format` correction are documented.
  No weakened tests, extra seam, bug fix or production move. Heavy commands
  use `nice -n 19`; Flutter runs are serialized. Stop here; feature-specific
  move/import/analyzer CI still enables only in Step 1's first production
  `lib/features/video_player/models/` file commit.

### 2026-10-11 — Step 0b addendum (original callers)

- **Revision.** Based on `31769235c`; detached original `849d3b343` remains
  byte-identical to S. Both independent samples and per-case closure are
  recorded in the deps report (initial 7/17 and second 9/12).
- **Results.** Negative-offset ChannelUp paging and exact direct-source
  rejection diagnostics close d13 and d5, each with a completed assertion
  failure on the original. Unmodified control: 55 behavior tests pass;
  one additional identity, all previous assertions retained.
- **Deviation.** d1 is equivalent through every original caller: forward
  comparisons are unchanged by clamping total to window end; reverse
  comparisons ignore total; merging reclamps to a containing window.
  The complete survivor run and exhaustive algebra/source audit are
  archived, rather than adding a private seam or claiming a false kill.
  Optional d2 rerun loops/timeouts are excluded; Claude's completed
  assertion kill is retained.
- **Commands/evidence.** `nice -n 19 python3 step0b-addendum/run.py`,
  `dart format` of the two changed test files, `git diff --check`;
  `step0b-addendum/` contains exact commands, patches, raw assertion logs,
  hashes and NOTEs. Application/dependencies unchanged; no allowlist.
  Flutter runs serialized; full additions-only comparison follows at
  the authorized Step-1 gate against the accepted Step-0b baseline.

### 2026-10-11 — Step 1 (production moves; CI activation)

- **Revision.** Follows addendum `8073fc9a2`. This creation commit applies
  the frozen 16-declaration move list into ten feature files, including
  `models/vp_manual_source_validation_failure.dart`; CI activates here.
  The manifest changes only status. All 893 fates, including S's two
  patched declarations/three interceptions, compare with zero differences.
- **Checks.** Current ownership/history, frozen seam negative proofs,
  analyzer comparator (74 scoped diagnostics, zero additions), global
  allowlist (45 inventoried warnings), size and architecture pass.
  Whole-file format proof: five optional commas inserted, none deleted;
  idempotent. Actual CI formatting scope: 2,321 files, no changes.
  Characterization/theme subset: 68 successful identities.
- **Structure/CI.** Facade 18,251→18,018; new files 3–65 lines. Exact
  bridge, facade back-import ban, pure import/type lists and 500-line caps
  are registered with real positive/negative probes. CI has full history,
  move self-test/current check, scoped analyzer and facade format/analyze
  paths. All ten theme paths and live reader/seam guards are retargeted;
  no source assertion removed. The rejection diagnostic expectation
  follows the declared public type rename.
- **Evidence/next.** `step1/` holds exact move/format proofs, source-reader
  and seam validation, analyzer and CI-scope logs. Six original warnings
  and one approved probe import warning are preserved, with no fixes.
  Full-suite identity comparison against Step 0b, all manifest self-tests
  and historical inputs, and both release builds run on the clean commit
  before the gate Progress entry. Dependencies unchanged; no devices.

### 2026-10-11 — Phase 1 gate (complete; stop)

- **Revisions.** Addendum `8073fc9a2`; production/CI creation
  `5faaed55b`. Gate ran on the clean production commit; the final gate
  record changes documentation only. Scope and frozen move list complete.
- **Suite.** `suite_evidence.py run/compare` against the accepted Step-0b
  run passes by identity: 12,852 successes, same 13 failures / 28 errors /
  20 skips; one added success, zero changed outcomes, missing tests, new
  failures or new skips. Profile editor passes; no test allowlist changes.
- **Checks.** Fresh analysis/comparator passes (74 scoped, zero additions;
  1,680 external diagnostic occurrences, identities/counts unchanged). Actual CI formatting scope, size
  and architecture pass. All 26 existing Dart manifest self-tests plus
  video-player self-test/current/`--at` P1/T/S comparisons pass. Kotlin
  checker historical/compiled self-tests pass. Parser audit: 147 isolated
  packages, 441 copied kernels deleted; all manifest flags under vplayer.
- **Builds.** `nice -n 19 flutter build apk --release --no-pub` and
  `flutter build macos --release --no-pub` succeed (120.56s / 221.76s).
  Both leave tracked files unchanged; artifacts/checksums archived.
- **Evidence/deviations.** `gate/COMMANDS-gate.txt`, `completion.json`,
  `suite-delta.json`, parser audit, checker/analyzer logs and release
  artifacts record the exact clean tree/SDK/results. d1 is proved
  caller-equivalent; d5/d13 assertion-killed on the original (addendum).
  No bug fixes, new seams or dependency changes. Heavy commands nice 19,
  Flutter suites serialized; no device, push, merge or branch switch.
- **Human checklist (end of series; not gates).** On phone, Android TV
  with Flutter player, tvOS and desktop: random menu tiles render/select;
  catch-up/Start Over cancellation beats slow lookup; identity labels
  unchanged; plain playlist entries resume saved progress. Pending.
  Stop here; gated-range review/integration remains with user/Claude.

### 2026-10-11 — Phase 2 Step T (complete; draft only)

- **Revision.** `6fdc85a66`, based on original `31a347ad2`, re-measured by
  name: 889 spans, 12 moved declarations, 14 retained reference sites.
  Complete raw/formatted evidence-only P2 materializations compare with
  zero differences; no production destination created.
- **Checks.** Opt-in owner-scoped bare-field positive and all binding
  negatives pass without changing old manifest behavior. All 26 existing
  Dart manifest self-tests, video-player universal self-test, historical
  P1 `--at 31a347ad2`, and Kotlin historical/compiled self-test pass.
  Analyzer root/strict/probe: 74/141/75 scoped occurrences, zero additions
  against maximum inventory; async-context declaration identities unchanged.
  Format idempotent, zero optional commas or introduced diagnostics;
  size/architecture pass. Commands/results: `p2/tooling/completion.json`.
- **Constraints.** Explicit isolated parser packages (copied kernels
  deleted), heavy processes nice 19, serialized Flutter runs. Application
  and pubspec unchanged; CI transition remains in the production creation
  commit. Step 0 continues on the original; no bug fixes or new seams.

### 2026-10-11 — Phase 2 Step 0 (original characterization checkpoint)

- **Revision/scope.** Follows T `6fdc85a66`; original application remains
  exactly `31a347ad2`. Twenty-one behavior tests use public controls/menu/guide
  callbacks, fake-player events and the existing storage boundary. No new
  seam, private-State call, production move or CI transition.
- **Coverage/proofs.** Systematic 81-point sweep over all 12 moved
  declarations and 14 retained reference sites: 68/68 reachable
  non-equivalent mutations assertion-killed, nine caller-equivalent, four
  platform/clock pending. All 21 final-input tests have assertion-failing
  original witnesses in the detached evidence worktree. Tables are in the
  deps report; `p2/step0/completion.json` pins commands, hashes and results.
  Invalid/uncaught-error attempts receive no credit; earlier attempts kept.
- **Checks.** `nice -n 19 python3 step0/run_mutations.py`, `dart format`,
  changed-test `dart analyze` (no issues), size (2,994/140 ratchets),
  architecture (1,662 migrated files), and diff checks pass. Full suite
  follows on this clean checkpoint, compared by identity to the exact
  reusable P1 observed baseline; dependencies/allowlists unchanged.
- **Deviations/pending.** Real countdown decrement was already approved
  device-pending. Android-only instance replacement while save is blocked,
  the false player-created path, and mobile playback-intent consumers
  cannot execute on the macOS VM without an unauthorized raw Platform seam.
  Explicitly pending under rule 4, not declared equivalent or covered.
  Legacy sleep sheet is dead. Disposed cancellation is reached by overlapping
  EOFs and its mode assignment has a behavioral mutation proof.
- **Existing outcomes.** Save released after dispose still calls the disposed
  player: native rejection propagates, success emits no toast. A previously
  issued live open can complete after sleep pause under the fake contract;
  the latch blocks later recovery. Recorded in Follow-ups; no bug fixes.
  Heavy commands nice 19, harness flag true, suites serialized; no devices.

### 2026-10-11 — Phase 2 tooling compatibility addendum

- First clean checkpoint `61fac9315` full suite completed with 21 added
  successes and one extra failure: the IPTV two-pane real-config checker
  fixture requires exactly one textual qualification-default anchor. T's
  new validation duplicated it; guard behavior was unchanged, but its
  default-substitution proof could not run. No failure was allowlisted.
- Shared guard now evaluates the existing default once and uses that value
  in both checks, preserving the fixture's single anchor and opt-in
  rejection. Full fixture/default probes and all affected manifest checks
  are rerun; Kotlin's separate checker inputs are unchanged.
  A new clean-tree full-suite run establishes the baseline after this fix.
  Application, app dependencies, tests and all guard assertions unchanged.

### 2026-10-11 — Phase 2 Step T / Step 0 final evidence (stop before moves)

- **Revisions.** T `6fdc85a66`; original characterization `61fac9315`;
  qualification-default compatibility correction `5b2b62c3b`. Application
  and pubspec remain byte-identical to `31a347ad2`; the P2 manifest stays
  draft. CI/source-test/theme registration waits for the creation commit.
- **Original proofs.** All 21 final tests have assertion-failing original
  witnesses. The 81-point campaign records 68 valid assertion kills, nine
  caller-equivalent points and four platform/clock-pending points. Per-run
  hashes retain earlier inputs; 16 final-input mutation reruns witness all
  21 final tests. Coverage/mutation tables and limitations are in the deps
  report and `p2/step0/completion.json`. Claude's independent sample remains
  the next review checkpoint.
- **Clean baseline.** On `5b2b62c3b`,
  `nice -n 19 python3 dev/tool/suite_evidence.py run vplayer/p2/step0-suite-final --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`
  completed with 12,873 successes, the same 13 failures / 28 errors / 20
  skips, and exactly 21 added passing identities. Strict identity comparison
  and `suite_evidence.py compare --against` the reusable P1 gate both pass:
  zero missing, changed, newly failing or newly skipped originals. No allowlist
  changes. First-attempt logs remain archived.
- **Tooling/checks.** All 26 existing Dart manifest self-tests, P2
  universal/real-config tests with original self-comparison, and historical
  P1 `--at 31a347ad2` pass after the correction. Kotlin's successful T
  historical/compiled self-test is reused with unchanged inputs. Parser
  audit confirms isolated packages under `.dart_tool/vplayer_parser/`,
  deleted copied kernels and explicit flags. Format, size and architecture
  pass. Commands/results: `p2/step0/compat-checks-effective.json`.
- **Analyzer/pending.** `flutter analyze --no-pub` source identities are
  unchanged; 16 additional warnings originate in ignored release-build
  copies of pubspec (recorded, unsuppressed). The scoped comparator and its
  negatives pass: 74 diagnostics, zero additions. Real-clock decrement,
  Android replacement/player-created-false during suspended save, and
  mobile intent consumers remain explicitly pending under rule 4. No new
  platform seam, bug fixes, production moves or device commands.

### 2026-10-11 — Phase 2 Step 0b addendum (independent sample accepted)

- **Original/sample.** Application `31a347ad2` is byte-identical to sample
  revision `61fac9315`. Claude: 18/21 compile-valid mutations killed;
  `e2` zero-boundary change equivalent, reported 18/20 = 90%, meets the bar.
  Full sample and both survivor resolutions are in the deps tables.
- **Survivors.** `e11` is caller-equivalent: off mode already has null
  deadline/zero preset, and removing the return adds only identical-value
  `setState` (or identical unmounted assignments). `e14` intent deletion
  remains device-pending, not equivalent: raw Android renderer fallback
  and Android/iOS Start Over/background consumers. Fallback also rejects
  resume via the already-set sleep latch. All reads inventoried.
- **Checks/baseline.** Original control plus exact `e11`/`e14` reruns pass
  all 76 executable characterization tests in the detached original,
  nice 19, serialized, with the hook define. Initial source-guard rejections
  are archived and earn no behavior credit. Evidence:
  `p2/step0b/runs.json`, `survivor-analysis.json`, `source-guard-attempt/`.
  No new tests/application changes; accepted `step0-suite-final.jsonl` at
  `5b2b62c3b` is unchanged and remains the step-0b observed baseline.
  Original mounted/disposed behavior is preserved; no bug fixes or seams.

### 2026-10-11 — Phase 2 Step 1 (production creation checkpoint)

- **Revision/scope.** Follows addendum `5205111eb`; applies the frozen P2
  draft: 12 declarations, 14 retained substitutions, exact controller/Host,
  eager State constructor, `_vpSetState` and live adapter. Application files
  byte-identical to accepted formatted T materialization; all P1 files intact.
  Direct dispose cancel/clear retains statement order. No bug fixes.
- **Registration.** Current/self-test and analyzer CI switch to P2 with its
  inventory; P1 stays `--at 31a347ad2`. Both sleep tests registered, hook
  define retained. Theme lists/expected lists include the new destination;
  EOF guards use validating current declaration text and non-negative anchors.
  Seam proof follows latest ownership while retaining frozen S assertions.
- **Checks.** 92 affected tests pass; removed/reordered EOF sleep branches
  assertion-fail in detached evidence materialization. Current move check
  zero diffs; analyzer/self-tests 75 scoped, zero additions; exact CI
  analyzer allowlist 45 existing warnings, no new/stale rows. Format,
  size/architecture and seam negatives pass. Controller 149 lines; facade
  ratchet 18,018 → 17,932. Evidence `p2/step1/completion.json`.
- **Tooling/pending.** Architecture fixtures honor phase evidence root;
  initial legacy P1 temporary copy auto-removed, accepted rerun under P2.
  No persistent earlier evidence overwritten. Clock/mobile cases remain
  device-pending; gate proceeds on the clean creation commit, compared to
  unchanged step-0b observed baseline. No device commands or new seams.

### 2026-10-11 — Phase 2 gate (complete; stop)

- **Revisions.** Addendum `5205111eb`; production/clean tested tree
  `b0533aac5`. Current P2 applied, all ten P1 destinations unchanged,
  application edits restricted to frozen facade/controller materialization.
  Pubspec unchanged. Commands/hashes/results: `p2/gate/completion.json`.
- **Suite.** `suite_evidence.py run vplayer/p2/p2-gate-suite --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true` (nice 19) completed: 12,873
  successes, same 13 failures / 28 errors / 20 skips. Strict identity
  equality and official compare against unchanged Step-0b observed baseline
  pass: zero added/missing/changed identities. No allowlist changes or flakes.
- **Checks.** P2 current/universal self-test/same-revision `--at b0533aac5`,
  P1 `--at 31a347ad2`, all 26 Dart manifest self-tests and complete Kotlin
  historical/compiled self-test pass. Isolated parser flags/audit pass.
  Analyzer comparator 75 scoped/zero additions, CI warning allowlist 45
  existing/nothing new or stale; non-video-player identities unchanged.
  Format, size/architecture pass; 149-line controller, 17,932-line facade.
- **Builds.** Sequential `nice -n 19 flutter build apk --release --no-pub`
  (114.31 s) and `flutter build macos --release --no-pub` (108.77 s) pass,
  no install/run. Tree clean after both; artifact/AOT hashes recorded.
- **Deviations.** Initial architecture copy used legacy P1 temp path and
  auto-removed; accepted rerun under P2 after phase-root support. Initial
  Kotlin run omitted its separate evidence override, was interrupted and
  earns no credit; complete explicit-P2 rerun passed. Raw batch retains
  that interruption; accepted ledger replaces only its row. Notes in deps.
- **Device checklist/pending.** Real countdown decrement/nonpositive branch;
  Android replacement/player-created-false during blocked save; `e14`
  Android/iOS Start Over/background intent; phone, Android TV (Flutter),
  tvOS and desktop sleep/EOF/save checks at series end. No new seams,
  bug fixes or device commands. Stop before Phase 3 and review externally.

2026-10-11 — **Phase 1 independent review (Codex `vp-rev1`, fresh session) on
`ed728b078..2eb4fda82`: P1 none, P2 none, P3 none — "No P1s".** It reproduced the format
proof, seam exactly-once/installation rules, 893-span ownership comparison, history and
binding negatives, 58 focused tests, mutation spot checks, equivalence/dead-code claims
(c15/c16/c18, d1/d8/d11/d12) and raw suite identities. Claude samples: first 7/17 (41 %,
step 0b + systematic sweep), after 0b 18/20 on the first set and 9/12 (75 %) on a second
independent set; d5/d13 then closed. Merged `--no-ff` into `refactor/codebase`.

2026-10-11 — **Phase 2 independent review (Codex `vp-rev2`, fresh session) on
`31a347ad2..7775198f5`: P1/P2/P3 none — "No P1s".** Reproduced ownership checks for 12
moves + 14 retained substitutions, P1 `--at`, protection of the ten P1 destinations,
bare-access negatives, 24 focused tests, e2/e11 equivalence and e14 device-pending, raw
suite identities and analyzer (zero additions). Claude sample 18/20 (90 %). Merged.

### 2026-10-11 — Phase 3 Step T (complete; draft only)

- **Revision/scope.** `c1d4cb51b`, approved design `de55d9987`, original
  `fc24e32ae` re-measured by name: 882 classified spans, 17 moves, 14
  substituted retained occurrences and three preserved notifier references.
  Raw/formatted complete evidence materializations compare with zero
  differences; existing State constructor is patched after its sleep assignment.
  All ten initializer inertness proofs and the State-owned notifier are recorded.
- **Checks.** All 26 existing Dart manifest self-tests, complete video-player
  universal/real-config self-test, P1 `--at 31a347ad2`, P2 `--at fc24e32ae`,
  and Kotlin historical/compiled self-test pass. All 11 earlier destinations
  protected. Analyzer root/strict/raw/formatted probe: 75/142/78/81 scoped
  diagnostics, zero additions to frozen maxima; async-context identities
  unchanged. Format idempotent, zero inserted/deleted optional commas; three
  brace infos exposed by formatting recorded. Size/architecture pass.
- **Evidence/deviation.** `p3/tooling/completion.json`, accepted 30-command
  ledger and parser audit. Initial new constructor negative used an invalid
  no-op edit; corrected fixture and complete universal rerun pass. No shared
  guard behavior change. Every Dart manifest has an explicit isolated parser
  package, copied kernels deleted; both evidence overrides active, nice 19.
- **Constraints.** Application/pubspec unchanged, P3 manifest draft, no
  production destination or CI transition. Creation commit must select P3
  current/self-test and analyzer manifest/inventory, retain both historical
  phases, register tests and extend all three theme lists. Step 0 continues
  on the original; no bug fixes, new seams or device commands.

### 2026-10-11 — Phase 3 Step 0 characterization checkpoint

- **Scope/revision.** `55ac577e6`, following Step T `c1d4cb51b`; original
  application
  `fc24e32ae` unchanged. Six new behavior files, two support helpers and the
  existing HTTP fixture's held/close trace. No new production seam or moves.
- **Behavior.** All 58 tests pass on the detached original. Settings/request
  gates, exact identity/key partitioning, cache/dedupe, held A→B→A success/error,
  cached returns without generation changes, media/reset/failed-load boundaries,
  all three profile cases, dispose, seek/clock/save/haptic, tracker heartbeat
  order and TV Select are pinned through original callers. Existing race and
  profile gaps recorded in Follow-ups without fixing them.
- **Sweep/proofs.** All 17 moved declarations and 17 retained occurrences:
  148 points, 119 assertion kills, 26 equivalents with caller/source arguments,
  three dormant/web/device classifications. Every new test has an assertion
  witness with final input hashes. First-pass survivors closed systematically;
  Claude's independent P3 sample remains pending. Deps report has complete
  coverage, mutation, equivalence and per-test witness tables.
- **Commands/evidence.** Serialized `nice -n 19 flutter test` with `--no-pub`,
  hook define and JSON reporter; `p3/step0/coverage.json`, `mutation-results.json`,
  `points.json`, raw/replay logs and detached worktree. Changed tests analyze
  cleanly; root `flutter analyze --no-pub`: 1,771, zero added/removed identities.
  Reusable P2 gate inputs/SDK equal the original (`baseline-reuse.json`).
- **Deviations.** Initial mutation file selection missed dynamically named
  tests; final runner discovers all six files. TV missing-seek exceptions
  excluded until explicit seek-count assertions killed both mutants. Initial
  clock callback's guarded test assertion corrected to post-pump trace assertion;
  original control/replays pass. Attempts retained, no allowlist additions.
- **Next/constraints.** Clean-tree additions-only full-suite baseline is recorded
  below. CI remains P2; P3 creation must register the six files and
  perform the documented transition. Provider replacement dormant; unavailable
  provider web-pending; player-created-false Android path and end-of-series
  device checklist pending. Pubspec unchanged; no device/build/run commands.

### 2026-10-12 — Phase 3 Step T / Step 0 final evidence (stop before moves)

- **Tested revision.** Clean `55ac577e6`; application remains byte-identical
  to `fc24e32ae`. `nice -n 19 python3 dev/tool/suite_evidence.py run
  vplayer/p3/step0-suite-final --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`.
- **Suite.** 12,931 successes / 13 failures / 28 errors / 20 skips. Strict
  identity equality against the reusable clean P2 gate: exactly 58 added
  successes; zero missing, changed, newly failing or newly skipped identities.
  Official comparison PASS; no allowlist changes. SDK Flutter 3.44.8 / Dart
  3.12.2; tree unchanged during the complete run.
- **Checks/evidence.** Root analyzer 1,771 before/after, zero identity additions
  or removals; changed tests clean; format, size (2,995 / 140 ratchets) and
  architecture (1,663 migrated files) pass. Step T's 30-command precedent
  ledger and Kotlin compiled self-test remain valid. `p3/step0/suite-delta.json`,
  `suite-comparison.txt`, `completion.json`; final-input 58-test witnesses and
  exhaustive 148-point tables in the deps report. Parser audit: 185 unique
  isolated invocation packages, 555 copied kernels deleted, 32 explicit
  manifest invocations, all nested parses routed under `vplayer_parser`.
- **Stop/remaining.** No production moves, CI transition, pubspec change,
  bug fixes, pushes/merges, branch switches, device/emulator/run/install or
  application builds. P3 independent Claude sample and the classified web/device
  checks remain pending. Stop at Step 0 for review.

### 2026-10-12 — Phase 3 Step-0b independent-sample addendum

- **Revision.** `682d86812`; tested original `55ac577e6`; application `55ac577e6` / `fc24e32ae`
  unchanged; documentation/evidence only.
- **Sample.** Claude 20/21 (95.2%). f9–f13/f20 false COMPILE-ERR labels
  corrected to assertion kills; saved tails lack assertion sections, so six
  complete original replays verify them. f2 replay passes all 134 tests.
- **Equivalence.** f2 strengthens sweep E11: skip preferences register before
  initialization's sequential defaults reads on the same cached future; positive
  duration cannot exist at the trailing sync. Paused late-settings case is
  unreachable through original callers. Preserve call unchanged; no new seam.
- **Commands/evidence.** Serialized `nice -n 19 flutter test` original behavior
  files, no-pub, concurrency 1, hook define, JSON. `p3/addendum/` contains full
  replay logs, normalized kill table, hashed caller/dependency proof and reuse
  NOTE. Systematic sweep unchanged (119 killed / 26 equivalent / 3 classified).
- **Baseline/constraints.** Reuse clean `55ac577e6` full suite; no test/app/input
  changes, no allowlist or pubspec edits, no device/run/install commands. Proceed
  to frozen Step 1 production moves and the clean-tree gate.

### 2026-10-12 — Phase 3 Step 1 production creation

- **Revision.** `575ead0ca`, following `682d86812`; tested source hashes in
  `p3/step1/materialization-application.json`; clean-tree gate follows.
- **Move.** 17 declarations, patched State constructor (sleep then skip),
  frozen Host/adapter, 14 retained substitutions + three unchanged notifier
  references; individual dispose positions and State-owned allocation retained.
  Controller 260 lines; facade 17,932 → 17,766. P3 manifest applied, zero diffs.
- **CI/source guards.** P3 current/self and analyzer manifest+inventory;
  P1/P2 historical checks retained; six test files and three theme lists added.
  Reader already chains live P3 declarations; no moved legacy anchor/weakening.
- **Commands/results.** `nice -n 19` ownership, format, size `--update`,
  architecture/negatives, root/CI analyze, scoped comparator and affected suite
  with hook define/no-pub: all 150 pass. Root 1,777 vs 1,771; six frozen-probe
  additions only, every outside identity unchanged; 81 scoped diagnostics pass.
- **Deviations/evidence.** Theme helper's one-occurrence assertion stopped;
  resumed for all three fixture lists after byte validation. Size updater's
  dated comments restored; no tree change during affected run. `p3/step1/`
  contains attempts, commands, inputs and results; no application bug fixes,
  pubspec changes, device/run/install, push/merge or branch switch.
- **Pending.** Clean-tree gate suite/builds/all self-tests/historical phases;
  classified web/Android paths and end-of-series device checklist remain pending.

### 2026-10-12 — Phase 3 clean-tree gate (stop)

- **Revision.** Tested clean production `575ead0ca`; gate commit follows it.
  Step-0b baseline remains clean `55ac577e6`, SDK/inputs pinned.
- **Suite.** Serialized `nice -n 19 python3 dev/tool/suite_evidence.py run
  vplayer/p3/p3-gate-suite --no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`:
  12,931 success / 13 failure / 28 error / 20 skip. Exact baseline identities
  and outcomes; official comparator PASS; no new failures/skips/allowlisting.
- **Checks.** Root/CI scoped analyzer 81, zero beyond frozen P3 inventory;
  root 1,777 with expected probe-only +6 and unchanged outside identities.
  CI format list, 2,996-file size check (140 ratchets), 1,664-file architecture
  and negatives pass. All 31 Dart/Kotlin self/current/history commands pass;
  P1/P2 historical revisions retained and earlier destinations protected.
- **Builds.** `nice -n 19 flutter build apk --release --no-pub` and
  `flutter build macos --release --no-pub`: both pass on clean creation;
  hashes/logs in `p3/gate/build-results.json`. No install/run/device commands.
- **Evidence/constraints.** `p3/gate/completion.json`, full suite/strict delta,
  analyzer/format/size/boundary logs, accepted checker ledger and parser audit.
  Every manifest uses an isolated VPlayer parser with copied kernels deleted;
  only declared application paths changed, pubspec unchanged, trailers checked.
  No pushes, merges, branch switches or bug fixes. Original mutations restored.
- **Pending/stop.** Web unavailable-provider and Android player-created-false
  paths; human end-of-series checklist on phone, Android TV Flutter, tvOS,
  desktop: button timing, seek end, TV Select and no old-button episode flash.
  Existing race/profile gaps remain unchanged in Follow-ups. Stop at Phase 3.

### 2026-10-12 — Phase 3 `vp-rev3` test-only review closure (stop)

- **Revision/review.** Closure follows `d6e91c62a`. Independent review:
  no P1s/P2s; the P3 incoming-provider coverage gap is closed by C59 while
  preserving the disabled incoming-profile case unchanged.
- **Original witness.** Exact detached `55ac577e6`: new behavior test passes;
  forcing the provider factory to keep SkipDB fails its IntroDB-request
  assertion (expected one, actual zero). Completed assertion kill, no
  compile/load errors; original application restored.
- **Commands/results.** Serialized `nice -n 19 flutter test` across all six
  skip files, `--no-pub --concurrency=1` and hook define: 59 pass on moved code.
  `check_dart_moves.py --manifest dev/tool/dart_moves/vplayer_p3.json` with
  explicit isolated parser: zero differences; copied kernels deleted.
  Changed-file `dart format` and `flutter analyze --no-pub` pass.
- **Evidence/scope.** `p3/review-closure/` records commands, hashes, mutation
  logs and completion; deps coverage/mutation addendum records C59. Existing
  CI registration covers the same file. Test/docs only, pubspec unchanged;
  no deviations, production changes, device commands or push/merge/branch
  switch. Stop after this review closure.

### 2026-10-12 — Phase 4 Step T (tooling checkpoint)

- **Revision/base.** Tooling follows approved `b6f1c2c50`; original re-measured
  by name at `890df14d8`: 868 original spans, 16 moves, 33 retained references.
- **Commands/results.** Complete evidence-only P4 materialization and
  all-retained self-compare report zero differences. Real-config widget
  selector registration, binding-only capture negatives, frozen live adapters,
  eager constructor/HUD/direct-write negatives pass. Evidence-only format is
  idempotent with no optional-comma or diagnostic changes; controller 243 lines.
  Root/strict/probe analyzer inventories: 81/149/82; async-context identities
  unchanged by declaration. All existing Dart manifest and Kotlin self-tests
  plus P1/P2/P3 merge-revision historical checks pass (`p4/tooling/checks.json`).
- **Constraints/CI.** Every manifest uses an explicit isolated parser under
  `.dart_tool/vplayer_parser/`, copied kernels deleted; heavy work uses nice 19.
  P4 drafts only, application/pubspec unchanged. CI transition deferred to the
  production Step-1 commit creating `vp_display_mode_controller.dart`.
- **Deviations.** No guard extension needed: the existing opt-in complete
  selector registration already preserves/rejects the required bindings.
  Failed development probes are archived and uncredited. Step 0 follows;
  no production moves.

### 2026-10-12 — Phase 4 Step 0 (characterization checkpoint)

- **Revision/base.** Follows tooling `1816a0ee5`; every mutation uses detached
  original application `890df14d8`, restored after each run. Main application
  and pubspec remain byte-identical to that named base.
- **Coverage/results.** All 38 new display cases pass on the original and
  current application. Every case has an assertion-failing original witness.
  Systematic 170-point sweep covers all 16 moved declarations and each of
  33 retained references: originally 157 kills / three equivalences; vp-rev4
  corrects this to 158 kills / two equivalences, with nine dormant points and
  one PiP device-pending reference. Added held reverse orientation and aspect
  auto-hide cases close both async/action branches;
  HUD-after-dispose observes the rendered notifier's unchanged value.
- **Commands.** Serialized `nice -n 19 flutter test` with no-pub, concurrency 1
  and `DEBRIFY_VP_TEST_HOOKS=true`; explicit P4 evidence overrides. Original
  38-case control and current `display-focused.jsonl` pass; format and changed
  test/support analyzer pass. Size/architecture: 2,996 files / 140 ratchets,
  1,664 migrated files pass. Detailed coverage/mutation tables in deps;
  `p4/step0/points.json`, `mutation-results.json`, `coverage.json` and logs.
- **Attempts/deviations.** Invalid native-gate and uncaught-error-only witnesses
  are uncredited and replaced by flow-valid assertion kills. Fixture corrections
  preserve requested behavior assertions. Two preliminary runs inherited the
  harness's P2 runtime default; only their 72 newly created directories were
  relocated into P4 using exact run bounds (`runtime-routing-note.json`). All
  accepted controls/mutations export P4. No assertion weakening or app fixes.
- **Baseline/remaining.** Fresh original full suite re-measured at `890df14d8`:
  12,932 success / 13 failure / 28 error / 20 skip; exact P3 gate outcomes plus
  the accepted incoming-profile case. The new additions-only clean checkpoint
  suite follows this commit. Phone portrait seed/PiP restoration and the
  end-of-series device checklist remain pending; dormant speed cycle/old menu
  fallback paths stay classified. CI transition and five-file registration
  accompany Step-1 production creation. Stop before production moves.

### 2026-10-12 — Phase 4 Step-0 baseline recorded (stop)

- **Revision/evidence.** Tested clean `5e08bb3a3`, tooling `1816a0ee5`, freshly
  re-measured original `890df14d8`; `p4/step0/completion.json` records SDK,
  commands, hashes, coverage, constraints and parser audit.
- **Suite.** Serialized nice-19 `suite_evidence.py run` with no-pub and hook
  define: 12,970 success / 13 failure / 28 error / 20 skip. Exactly 38 added
  successes versus original; zero missing/changed original identities or
  new failures/skips. Official comparator PASS; no allowlisting.
- **Final checks.** All 38 cases mutation-proven. The count of 157 kills and
  three equivalent points is superseded by vp-rev4: 158 killed / two equivalent / nine
  dormant / one device-pending across 170 points and all 33 references.
  All 31 tooling/self/history checks pass; format, analyzer probes and test
  analyzer, size/architecture pass. Explicit isolated parser audit: no
  violations. Main and original application/pubspec unchanged, original
  mutations restored, tree clean during complete suite, required trailers.
- **Stop.** P4 remains draft; no production moves, CI activation, bug fixes,
  builds/device commands, push, merge or branch switch. Five test registrations
  and current/analyzer transition belong to Step-1 production creation.
  Phone portrait/PiP and end-of-series device checklist remain pending.

### 2026-10-12 — Phase 4 Step-1 production creation

- **Revision.** Creation follows `61c081e33`; frozen sources/hashes/commands in
  `p4/step1/completion.json`. Original remains named `890df14d8`.
- **Independent review sample.** Original `5e08bb3a3`: 19/20 raw; g20 pure
  enum-field read/scale computation is equivalent, agreed with Claude;
  19/19 valid = 100%, assertion kills only. Deps table and
  `p4/step1/independent-sample.json` record every witness. No addendum needed.
- **Applied.** 16 frozen declarations, exact 14-member Host/adapter and eager
  `_display` append; 33 retained occurrences; direct resume/default writes;
  both HUD notifiers stay State-owned. Controller 243 lines; facade 17,592.
- **Commands/results.** Nice-19 P4 current checker: zero differences. Serialized
  hook-defined/no-pub affected suite: 189 successes, no failure/skip.
  Exact CI format, 2,996-file size / 140 ratchets, 1,665-file architecture and
  negatives pass. Scoped analyzer 82 / zero additions; root 1,778 with expected
  probe-only +1 and identical outside identities. Existing warning allowlist
  and all earlier analyzer mappings preserved.
- **CI/source guards.** Current/self/analyzer → P4, P1/P2/P3 historical merges
  retained; five display test files registered. Validating reader chains P4;
  theme's three lists, rendered set and manifest extended. No assertion edits.
- **Constraints/next.** Exact proven formatted bytes, zero optional-comma
  changes and formatting diagnostics, pubspec unchanged; isolated parser and
  evidence overrides. No bug fixes, push, merge, switch or device commands.
  Clean creation gate follows; manual end-of-series checklist remains pending.

### 2026-10-12 — Phase 4 clean-tree gate (stop)

- **Revision.** Tested clean production `9cae15e31`; gate commit follows it.
  Accepted original-caller baseline `5e08bb3a3`; original base `890df14d8`.
- **Suite.** Serialized nice-19 `suite_evidence.py run vplayer/p4/p4-gate-suite`
  with no-pub and `DEBRIFY_VP_TEST_HOOKS=true`: 12,970 success / 13 failure /
  28 error / 20 skip. Exact Step-0 identities/outcomes, SDK and runner flags;
  official comparator PASS. Zero new regressions/skips or allowlisting.
- **Checks.** Scoped analyzer 82 / zero additions, root 1,778 with frozen +1;
  outside identities exact and previous mappings retained. Exact CI format,
  2,997-file size / 140 ratchets, 1,665-file architecture and negatives PASS.
  All 32 self/current/history commands PASS: all existing Dart manifests,
  universal real configurations/negatives, P4 current, historical P1/P2/P3,
  Kotlin self-test. Every manifest parser isolated with copied kernels deleted.
- **Builds.** Nice-19 `flutter build apk --release --no-pub` and
  `flutter build macos --release --no-pub`: PASS on clean creation; artifacts
  and AOT hashes/logs recorded. No install/run/device commands.
- **Evidence/constraints.** `p4/gate/completion.json`, exact suite delta,
  analyzer identities, checker ledger, parser audit, build results. Exact two
  frozen application paths and pubspec unchanged; branch/trailers/clean tree
  and original mutation restore verified. No bug fixes, push, merge or switch.
- **Pending/stop.** Phone portrait seed and PiP restore; end-of-series manual
  phone/Android TV Flutter/tvOS/desktop framing (incl. cinema zoom), rate/resume,
  phone temporary hold and orientation checklist. Dormant speed/menu branches
  remain classified. Phase 4 complete; stop before further production moves.

### 2026-10-12 — Phase 4 vp-rev4 closure (test/docs-only; stop)

- **Review/revision.** No P1s, one P2: defaults-await input exposes the aspect
  initializer. The previous equivalence claim was wrong. This review-only
  commit follows `794b1238c`; detached original is exactly `5e08bb3a3`.
- **Characterization.** C39 holds real preference loading, presses A and pins
  Cover HUD/icon, the preserved uninitialized-player zoom error, zero early
  saves, 1.5 s clear, defaults override and working ready zoom/resume save.
  C40 uses a real early pointer hold/release and pins the null-prior return.
- **Initializer audit.** Aspect mutation assertion-fails Cover vs Fit Width;
  speed mutation fails 1.0 vs 1.25 after defaults; non-null prior mutation fails
  expected-no-error on early release. Landscape mutation survives both cases:
  synchronous initState overwrites it before orientation/async work/input.
  Named-source ordering and original restoration recorded; no private caller.
- **Corrected matrix.** 40 display cases, every case mutation-proven; unchanged
  170 points / 16 declarations / 33 references: 158 killed, two equivalent,
  nine dormant, one PiP device-pending. Deps tables corrected; archived
  original evidence retained, superseded by `p4/vp-rev4/coverage.json`.
- **Commands/results.** Nice-19, serialized no-pub/hook-defined original
  control/mutations and moved focused suite: 40 successes. Changed format and
  test analyzer PASS; P4 current checker zero differences with an isolated
  parser/copy-kernel deletion. Evidence `p4/vp-rev4/completion.json`.
- **Scope/stop.** Test/docs-only; existing CI test files already registered.
  Application/pubspec unchanged; early error preserved. No new seam, bug fix,
  allowlisting, full-suite/build repeat, device commands, push, merge or switch.
  Manual phone portrait/PiP/end-of-series checklist remains pending. Stop.

## Design review round 1 resolution (Codex `vp-design`, 2026-10-11)

| Finding | Resolution |
|---|---|
| P1-1 Kotlin slot construction illegal in Dart; `setState` via adapter; owner identity `this` | Construction rule (eager assignment in one State constructor body; per-initializer inertness proofs; effectful initializers stay); `_vpSetState` forwarder; `host.pipOwner`/`visibilityOwner` substitutions pinned by occurrence; captured locals stay locals (rule 3). |
| P1-2 H1 under-specified | Three interception points in one hook, order preserved, test-mode-only installation, token proof; fake player/native platform/video controller contract; environment fixture; PiP device-pending ("Characterization harness"). |
| P1-3 `--at` leaves earlier destinations unprotected | Current-tree protection of every earlier destination, history-derived coverage, frozen scaffolding, same-revision `--at` inputs, negative (rule 2). |
| P2-4 impure "pure helpers" | Frozen phase-1 list; random/percent/dock excluded; per-helper proof; drop, never transform. |
| P2-5 phase map coupling | Shared-state section; phase 3 split into 2/3/4/7, title search split from tracks/menu, subtitle ownership map + M2, IPTV as one milestone, integration gates M1–M5, multiple destination files. |
| P2-6 reuse checker core | Thin ownership/history layer over the existing comparison and binding modules; optional-comma discipline; explicit baseline raise. |
| P2-7 source-test inventory | Exact table; validating, chaining reader; theme path lists. |
| P2-8 naming | `Vp`-prefixed public data types; typedef for `_RandomChoiceTile`; gate re-export; manual-source and season/episode scenarios. |
| P2-9 CI/analyzer/exceptions | CI registration in phase 1; scoped identity comparator; D6 bounded exception; per-phase profile/resource evidence. |
| P3-10 wording, baseline reuse | D4 reworded; baselines reused across mechanical moves. |

## Design review round 2 resolution (Codex `vp-design`, 2026-10-11) — "No P1s"

P2s folded: exact hook installation (assert-only assignment, release/profile
throw, test-only compile-time flag, source guard permitting only the
installer, exactly-once proof over helpers); declared `static` removal and
opt-in `_host` property/increment/owner-identity support in the shared
guards; `Random()` removed from inert examples, no Host reads at
construction, eager/lazy modifiers preserved; the hash characterization
targets the fallback resume identity. P3s: two patched declarations with
three patches; fake `track`/`tracks`; `ProfilePolicyGuard` mirror; exact
helper names and imports; follow-ups mirror D1/D6 exits.

## Phase 2 design review resolution (Codex `vp-design`, 2026-10-11) — "No P1s"

P2s folded: countdown decrement device-pending (real `DateTime.now()`, no
clock seam); step T owner-scoped bare field access + full P2 manifest +
CI transition (P1 `--at 31a347ad2`); `player_auto_next_routing_test`
anchor asserted non-negative; disposal during an in-flight fire and the
latch against queued advance / live recovery. P3: line numbers, comment
span, latch inventory (4321, 14317), "every member used", frozen `_host`/`_s`
fields, exact imports.

## Phase 3 design review resolution (Codex `vp-design`, 2026-10-11) — "No P1s"

P2s folded: profile-switch outcomes characterized as-is (no profile guard
exists); A→B→A same-key overlap, media-boundary clear and failed-load
re-arm; `_activeSkipSegmentUi` stays State-owned (debug allocation event
order); HTTP harness transport, dormant replacement, web-only
unavailable provider. P3s: concrete CI/manifest transition, patched State
constructor, theme lists; line/label wording; frozen Host signatures and
imports.

## Phase 4 design review resolution (Codex `vp-design`, 2026-10-12) — "No P1s"

P2s folded: orientation completion after disposal / overlap / rejection;
resume sampling across queued writes and the speed-1.0 skip; rendered
aspect contract (fit, custom ratio, numeric ratio). P3s: explicit
`widget.` selector registration with frozen adapter bodies and negatives;
33-reference ledger incl. 13722, `_changeSpeed` dormant, portrait seed and
PiP restore device-pending. Moving the four values (single storage
location, retained callers write the controller fields directly) accepted.
