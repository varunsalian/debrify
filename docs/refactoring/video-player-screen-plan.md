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

**Phase-8 platform checkpoints S2 / S2b.** S remains unchanged. S2 adds
only the approved PiP/background predicate sites below. On 2026-10-13 Claude,
the plan owner, approved **S2b** as a separately committed seam extension:
reuse `VpS2Hooks.isAndroid` at the renderer-mode load in `_initializePlayer`
and the renderer fallback eligibility argument in `_canFallbackExplicitRenderer`.
These two real Android guards otherwise prevent a desktop S2 test from creating
a replacement player inside the same State while iOS handle delivery is held
(sample k2); the later player-engine phase also needs these predicates covered.
Native defaults still evaluate the original predicate once and in its original
order. No new hook or installer. Exact declaration patches, independent site
default/order negatives, source guard and S/S2 proofs are required as for S2.
S2b stops for its own independent review before k2 characterization or moves.

**Phase-10 platform checkpoint S2c.** Extend the same `VpS2Hooks.isAndroid`
getter at only the renderer rejection guard in
`_setSubtitleTrackWithDiagnostics`. The hook and installer, S and the accepted
S2/S2b ledger stay frozen. A Phase-10 checkpoint ledger declares the single
before→after patch against `5c7b704bd`, retains every other facade declaration
and protects earlier destinations through history. Independent site negatives
and actual-body native-default/order witnesses precede independent review;
bitmap rejection/acceptance characterization follows at Step 0.

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
| 5 | Trakt scrobbling (2041–2750 Trakt subset) | 280 | med |
| 5b→6 | Simkl + MDBList scrobbling — **inserted as phase 6**; every later phase below shifts by one (provisional numbering) | 350 | med |
| 6 | Local completion (1820–1870, 10374–10478) | 160 | med |
| 7→8 | PiP + background/wakelock (11635–11882) — reviewed platform-predicate seam S2 (renumbered: phase 8) | 250 | high |
| **M1** | integration gate: controls/tracker/lifecycle scenarios | | |
| 8 | Subtitle engine I: subtitle settings, sync overlay, auto-sync pill/notice (2940–3088 auto-sync part only, 6380–6626) | 450 | med |
| 9 | Subtitle engine II: apply + diagnostics + failure + rollback (5014–5200, `_SubtitleApplyAttempt` users) | 300 | high |
| 10 | Subtitle sources and preferences: restore, default audio/subtitle language, forced, addon fetch/auto-select, Stremio download, priority (17164–18044) | 880 | high |
| **M2** | subtitle integration gate after phases 9–11 (renumbered) — see the phase-9 section | | |
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

## Phase 5 — Trakt scrobbling (trackers, part 1 of 2)

Branch `refactor/vplayer-p5` off the phase-4 merge `315028407`. Evidence
`refactor-evidence/vplayer/p5/`. Line numbers at `315028407`.

**Split (design review P3):** the trackers run as two consecutive phases
— **phase 5 Trakt**, **phase 6 Simkl + MDBList** — each with its own
manifest, step 0, Claude sample, gate and review (two "phase 5"
manifests would violate the history checker's uniqueness rule). Later
phase numbers in the map shift by one; numbering stays provisional.

### Moves → `presentation/legacy_video_player/vp_trakt_scrobbler.dart`

`VpTraktScrobbler` + `VpTraktScrobblerHost` (≈ 280 lines; 228 method
lines). Fields (1483–1491, with their comments; initial values `false` /
implicit `null` — inert): `_traktScrobbleEnabled`,
`_launchTraktPercentSpent`, `_traktEpisodeProgress`,
`_traktLastScrobbleAction`, `_traktHeartbeatTimer`. Methods:
`_initTraktScrobble`, `_traktProgress`, `_traktScrobble`,
`_startTraktHeartbeat`, `_stopTraktHeartbeat`, `_traktScrobbleSeek`,
`_currentEpisodeTraktPercent`. Leading comments follow checker ownership:
the Trakt percentage documentation at 2315 currently belongs to the
retained binder and stays with it unless the manifest reassigns it
explicitly.

**Stay State-owned:** `_persistablePosition`, `_traktSeasonEpisode`,
`_resumeTrackingAfterValidationGate`, `_bindEpisodeTrackerProgressIdentity`,
the analytics heartbeat, **`_resumeWriteGuard`, `_stremioTvStartupSeek`,
`_episodeTrackerProgressImdbId`** (borrowed by `_traktScrobbleSeek`, which
cancels deferred startup seeking and releases the resume-write guard
**before** checking validation or Trakt enablement, 1945 — those actions
must still run with Trakt disabled), all Simkl/MDBList members (phase 6).

**Host `VpTraktScrobblerHost` (21 members, frozen at step T):** the common
eleven — `mounted`, the validation-gate state, playing, duration, five
nullable string identity getters, `({int? season, int? episode})
traktSeasonEpisode()`, `bindEpisodeTrackerProgressIdentity(String)` — plus
the `widget.traktScrobble` boolean (live P4 selector registration, along
with `widget.contentImdbId`/`contentType`), `Duration get
persistablePosition`, the two seek guards (typed getters), series/active
playlist, current index, effective type/season/episode. No `context`,
`setState`, player or callbacks. Simkl's two calls to `_traktProgress()`
(2036, 2089) become `_trakt.traktProgress()` retained substitutions in
phase 5 (Simkl is still in the State); in phase 6 they become a
`double traktProgress()` member of the Simkl Host forwarded by the facade —
never a sibling import.

**Retained references** (from the review's 89-reference ledger, Trakt
subset, re-measured at step T; statement order preserved): initialization
1683; validation resumption/cache reset 2292–2302/2321–2323; player
subscriptions 3582/3621/3627/3650–3682; EOF 4987–4991; switch
restoration/advance 9321/10291/10392–10414; disposal 11701–11707 (each
statement in place, with the analytics cancellation between the Trakt
operations); launch budgets/percent reads 11976–11981/12004/12014/
12029/12103–12105; seek dispatch 11509, 12786, 12855, 13343, 13441,
14425–14441, 14977; Simkl's 2036/2089. The **skip adapter**
(`_VpSkipSegmentHostAdapter`, in the facade at 17457, forwarder 17497)
becomes a P5 **`patched`** facade declaration with one exact counted
receiver rewrite (`_traktScrobbleSeek` → `_trakt.traktScrobbleSeek`),
reason and test evidence — not an `earlier_patches` entry (that mechanism
accepts only history-derived destination files, `dart_move_history.py:60`);
the P3 controller/Host stay untouched.

**Scaffolding:** patched State constructor appends `_trakt` after
`_display`; `_VpTraktScrobblerHostAdapter`; CI: current/self-test and
analyzer inputs → P5; P1–P4 `--at` (`31a347ad2`, `fc24e32ae`, `890df14d8`,
`315028407`); protect all 13 earlier destinations; theme manifests and
every corresponding source-guard list; new tests in the curated CI list.

**Source-text guard retarget:** `test/android_tv_mdblist_progress_source_test.dart:157`
slices `_bindEpisodeTrackerProgressIdentity` … external-audio comment and
expects `final imdbId = _currentSeriesImdbId`; the three percent readers
leave that slice across phases 5–6. Use the validated source reader for
each moved percentage declaration and assert its live
`currentSeriesImdbId` forwarding and identity rejection; keep the retained
TVMaze identity and rewatch assertions; never a file-existence check.

### Step 0 — characterization of the original

**Harness:** one delegating HTTP transport installed before any tracker
singleton's first use and kept for the test isolate, dispatching to the
current case's recorder/barriers (the existing adapter,
`video_player_environment.dart:83`, records POST bodies and supports
delayed/error replies); synthetic credentials seeded through the storage
APIs; tracker caches/session revisions reset between cases; independent
auth barriers via `DeviceKeyProvider.debugInstallCipher` (controllable
`open`, `device_key_provider.dart:210`). No application seam.

**Trakt protocol (exact requests and absences per event):** start on
play, pause, stop with progress, the `> 80` transition (exactly 80 vs 81),
heartbeat timing/stop on pause/EOF/dispose, repeated actions and
`_traktLastScrobbleAction` dedup, failed sends and subsequent dedup,
launch-percent budget spent once, per-episode progress after a playlist
switch, custom identity and unresolved S/E. Initialization awaits
policy/auth **without a catch** (1739): pin propagated
initialization/storage errors separately from swallowed HTTP failures.
**Seek:** a user seek with Trakt disabled and with validation active
still cancels the deferred startup seek and releases the held resume
position. **Async readers:** `_currentEpisodeTraktPercent` captures a show
id, awaits storage, then reads the current episode, rejecting only on
`_episodeTrackerProgressImdbId != imdbId` (2326) — pin same-show episode
change, different-show rejection, A→B→A overlap, concurrent tracker reads
resetting the shared cache, profile change/disposal during initialization
and snapshot loading; gaps go to Follow-ups. **Early windows:** each moved
initializer observed before async loads complete, or justified
unreachable. Mutation proofs, coverage matrix, Claude sample.

### Device checklist (end of series)

With Trakt connected: start/pause/seek/stop for a movie and a series
episode; watched at > 80 %; progress resumes elsewhere; disabled → no
requests, seeks still release resume.

## Phase 6 — Simkl and MDBList scrobbling (trackers, part 2 of 2)

Branch `refactor/vplayer-p6` off the phase-5 merge `ea7901ead`. Evidence
`refactor-evidence/vplayer/p6/`. Line numbers at `d019a0765` (phase-5
gate, facade 17,394); re-measure by name at the phase base. Precedent:
phase 5 (its Host shape, HTTP transport harness, selector registration,
patched-adapter rule, async-reader cases and the stabilized snapshot
fixture apply unchanged).

Two sibling collaborators, no sibling imports.

### Moves

**`vp_simkl_scrobbler.dart` — `VpSimklScrobbler` + `VpSimklScrobblerHost`
(≈ 250 lines; 205 method lines):** fields (interleaved block 1484–1497,
moved individually; comment ownership by checker) `_simklScrobbleEnabled`,
`_launchSimklPercentSpent`, `_simklEpisodeProgress` (with its comment),
`_simklLastScrobbleAction`, `_simklHeartbeatTimer`; methods
`_initSimklScrobble` (with the "Simkl scrobble machine" section comment,
which names `_traktProgress()` — comments move verbatim, never edited),
`_simklSeriesSEUnresolved`, `_simklScrobble`, `_startSimklHeartbeat`,
`_stopSimklHeartbeat`, `_simklScrobbleSeek`, `_currentEpisodeSimklPercent`.

**`vp_mdblist_scrobbler.dart` — `VpMdblistScrobbler` + Host (≈ 200
lines; 142 method lines):** fields `_mdblistEpisodeProgress`,
`_launchMdblistPercentSpent`, `_mdblistSession`; methods `_mdblistTarget`,
`_initMdblistScrobble`, `_updateMdblistPosition`, `_mdblistPlay`,
`_mdblistPause`, `_mdblistStop`, `_mdblistScrobbleSeek`,
`_switchMdblistTarget`, `_currentEpisodeMdblistPercent`.

Initializers: `false` / implicit `null` — inert. The MDBList session is
allocated inside `_initMdblistScrobble`, not by a field initializer —
timing preserved.

**Stay State-owned:** `_episodeTrackerProgressImdbId` (in the middle of the
field block), `_analyticsHeartbeatTimer`, `_persistablePosition`,
`_traktSeasonEpisode`, `_bindEpisodeTrackerProgressIdentity`,
`_resumeTrackingAfterValidationGate`, the seek guards.

**Hosts** (design review measured 19 Simkl / 15 MDBList members; re-freeze
at step T): common — `mounted`, validation-gate state, playing, duration,
five nullable identity getters, `traktSeasonEpisode()`,
`bindEpisodeTrackerProgressIdentity(String)`; Simkl adds the
`widget.simklScrobble` selector, **`double traktProgress()`** (facade
forwards to `_trakt.traktProgress()`; step T registers the full chain
`_trakt.traktProgress` → `_host.traktProgress` at both occurrences (1844,
1897) via `registered_occurrence_substitutions.py:17`, freezes the adapter
body `double traktProgress() => _s._trakt.traktProgress();` and adds
receiver/capture negatives — ordinary host property bindings reconstruct
only bare names), playlist/index/effective-episode members; MDBList adds the
`widget.mdblistScrobble` selector, position, persistable position and
`Future<void> get playerInitializationFuture`.

**Retained references** (≈ 60, measured at step T; statement order
preserved, including the MDBList update preceding validation resumption
and the Trakt → Simkl → MDBList order in every fan-out): initState
1677/1678; validation resumption/cache reset; player subscriptions
(3332–3432 region); EOF (4739–4741); switch restoration/advance (9071,
10041, 10144–10164); disposal (11454–11457 in place); launch budgets and
percent reads (11728–11731, 11764/11779, 11856/11857); seek dispatch
(11260/11261, 12539/12540, 12608/12609, 13096/13097, 13194/13195,
14178–14193, 14730/14731); the skip adapter's two remaining tracker
forwarders (17301/17303) → a P6 `patched` facade declaration keeping P5's
Trakt rewrite and adding two counted receiver rewrites (carry the P5
`patched_class_projection` registration forward; no `earlier_patches`); the `_VpTraktScrobblerHostAdapter`'s
`bindEpisodeTrackerProgressIdentity` unchanged.

**Scaffolding:** patched State constructor appends `_simkl`, then
`_mdblist`; two adapters; CI current → P6, P1–P5 `--at` (`31a347ad2`, `fc24e32ae`, `890df14d8`, `315028407`, `ea7901ead`); protect all 14
earlier destinations; theme/source-guard lists; in
`android_tv_mdblist_progress_source_test.dart` (already on the validating
reader since P5) the Simkl/MDBList expected prefixes change from `_` to
`_host.`, keeping the capture/rejection and TVMaze/rewatch assertions, with
an independent failing mutation of each new adapter.

### Step 0 — characterization of the original

Reuse the phase-5 isolate-wide delegating HTTP transport, credential
seeding, cache/session reset and cipher barrier. **Simkl:** play stamps a
local `start` marker without POSTing; heartbeats POST **pause**; the
defensive `_simklScrobble('start')` branch with no live caller is
classified dormant; `> 80` transitions (80 vs 81); dedup on repeated
actions and after failed sends; unresolved series S/E; launch budget;
per-episode progress. **MDBList:** play checkpoints through **pause**;
sub-threshold exit sends pause (`mdblist_scrobble_session.dart:226`);
completion `>= 80` (exactly 80); target switch on source/episode change;
only player-initialization failure is caught (other init errors
propagate — pin both); gated disposal (`_mdblistStop()` returns at its gate
while `session.close()` still runs, 11457); the production singleton keeps
its first client (`mdblist_service.dart:58`). **Both:** the fan-out order
on play/pause/seek/EOF/dispose across all three trackers (Trakt now moved);
async percent readers (same-show episode change, different-show
rejection, A→B→A, concurrent reads resetting the shared cache, profile
change/disposal during init and snapshot load); early windows for every
moved initializer. **Disabled vs disabling:** both initially disabled
playback and disabling each tracker while its session stays active (Simkl
loads enablement once, 1809, and its send path does not recheck targets,
`simkl_service.dart:1101`; MDBList checks policy only at init) — record
actual requests after pause, heartbeat, seek and exit; any continuation is
a Follow-up, never fixed here. **Pending work:** hold an outgoing MDBList
checkpoint, start an episode/source switch, dispose or change profile,
release — assert outgoing/incoming target payloads, later requests,
revision notifications and timer cleanup (`switchTarget` and `close` wait
for sends, session 134/171; disposal closes unawaited, 11457); hold a Simkl
response across retirement incl. the service-owned 409 recovery (25 s
retry outliving the route, `simkl_service.dart:1183`); drain pending work
before attaching another fixture. **Startup and heartbeat:** auth
before/after playing and positive duration (Simkl arms its heartbeat only
when playing with positive duration, 1822; the first usable-duration event
starts MDBList, 3377); MDBList init while player setup is suspended (its
sequence at 1998 — policy, player-init await, mounted, captured target,
capability await, mounted, allocation, raw-position update, assignment,
conditional play — and captured locals preserved); the 2-minute interval,
cancellation on pause/EOF/dispose, Simkl's heartbeat keeping the local
`start` marker so a later real pause still sends, same-side seek silence vs
threshold crossings. Mutation proofs, coverage matrix, Claude sample.

### Device checklist (end of series)

With Simkl and MDBList connected: start/pause/seek/stop for a movie and
a series episode, watched at the threshold, progress visible elsewhere;
trackers disabled before playback send nothing; disabling one mid-playback
behaves as characterized (continuation, if any, is a recorded follow-up).

## Phase 7 — local completion tracking

Branch `refactor/vplayer-p7` off the phase-6 merge `2defa5100`. Evidence
`refactor-evidence/vplayer/p7/`. Line numbers at `6d2ac75d8` (pre-phase-6
moves; ≈ −360 after phase 6) — re-measure by name.

### Moves → `presentation/legacy_video_player/vp_local_completion.dart`

`VpLocalCompletion` + `VpLocalCompletionHost` (≈ 190 lines).

| Original | Kind |
|---|---|
| `_currentEpisodeMarkedAsFinished` 1388, `_currentMovieMarkedAsFinished` 1389, `_currentMovieRewatchStarted` 1390 | fields `false` |
| `_movieCompletionThreshold` 1391, `_episodeCompletionThreshold` 1393 | fields initialized from storage constants (verify `const`/static → inert, else stay State-owned) |
| `_forceLocalCompletionTracking` 1702 (declared mid-class, after its getter) | field `false` |
| `_loadLocalCompletionThresholds` 1681, `_loadTrackingPolicy` 1704 | async loaders |
| `_usesLocalCompletionTracking` 1694, `_currentLocalMovieImdbId` 1720 | getters |
| `_resetLocalCompletionState` 1726 | method |
| `_markCurrentEpisodeAsFinished` 9855, `_markCurrentMovieAsFinished` 9901, `_checkAndApplyLocalCompletion` 9925 | methods |

**Stay State-owned:** `_resumeKey` (read by the movie mark), playlist /
index / effective identity, position/duration, validation gate.

**Host** (exact at step T): `mounted`, widget `traktScrobble` /
`simklScrobble` / `mdblistScrobble` / `stremioTvChannels` / `contentType` /
`contentSeason` / `contentEpisode` / `contentImdbId` / `contentTitle` /
`title` (live selectors), `effectiveIptvChannels`, `effectiveContentImdbId`,
`effectiveContentType`, `seriesPlaylist`, `activePlaylist`, `currentIndex`,
`position`, `duration`, `validationGateActive`, `resumeKey`.

**Membership (re-measured at `2defa5100`, 14 declarations):** flags
1392/1393/1394, thresholds 1395/1397 (both reference the `static const int`
`LocalCompletionStorage.defaultLocalCompletionThreshold`,
`local_completion_storage.dart:29` — inert), mid-class force-local flag 1696,
loaders 1675/1698, getters 1688/1714, reset/episode mark/movie mark/check
1720/9460/9506/9532. ≈ 163 lines move; 21 Host getters (live widget
selectors, the local `seriesPlaylist` snapshot preserved); no `context`,
`_vpSetState`, owner identity or sibling collaborator; no tracker adapter
needs patching. Imports: `dart:async`, the four completion/resume storage
modules, tracking policy, the three legacy playlist/channel types.

**Retained references (11 occurrences, frozen ledger):**

| Responsibility | Facade lines |
|---|---|
| Policy / threshold startup (skip-settings call stays between them) | 1628, 1630 |
| Position dispatch | 2940 |
| EOF episode / movie marks | 4348, 4352 |
| MagicTV / Stremio TV / playlist resets (playlist reset after MDBList target switching and the mounted/request check) | 5237, 9030, 9770 |
| Resume restore movie identity | 11404 |
| Resume-save flag and identity reads | 11848 (twice) |

**Scaffolding / CI:** patched State constructor appends `_completion` after
`_mdblist`; adapter; switch current/self-test (`checks.yml:77`) and **both**
analyzer manifest and inventory (line 99) to P7; P1–P6 `--at` incl. P6
`2defa5100`; protect all 16 earlier destinations; register tests in
`ci_behavior_tests.txt` and the destination in `theme_surface_manifest.txt`,
`theme_rendered_set.py` and all three lists in
`test/theme/source_guard_test.dart`; preserve the moved episode method's
`empty_catches` diagnostic identity (not a changed count).

### Step 0 — characterization of the original

Threshold load and tracking-policy load (forced local while scrobbling),
`_usesLocalCompletionTracking` truth table, movie rewatch/mark, series
single-file vs playlist paths, validation/zero-position/zero-duration
short-circuits, resets, resume reads — plus, from the design review:

- **Cross-profile writes (pin as-is):** hold delivery after profile A's
  read in the episode mark (`episode_completion_storage.dart:20` →
  `playback_state_store.dart:33` re-acquires preferences) and the movie
  mark/unmark (`movie_progress_storage.dart:55`, `:82`), complete the public
  profile handoff, release; assert **both** profiles' physical preference
  contents, completion notifications, cleanup and resume records; include
  disposal while held. The stale-instance guard
  (`profile_preferences.dart:296`) does not reject a newly obtained B
  instance, so A's map can land in B — **recorded in Follow-ups, preserved
  by this move**. Check the resume-removal branch separately (scoped
  database operations).
- **One-shot is position-dispatch only:** the episode mark checks neither
  its flag nor local-tracking enablement (9460) and EOF calls it directly
  (4348); the playlist path sets the flag before validating index/metadata.
  Cover threshold→EOF, repeated/overlapping EOF, tracker-enabled EOF,
  missing metadata/index; assert writes, timestamps/revisions, later retry;
  preserve EOF order: tracker stops → awaited episode mark → awaited movie
  mark → sleep/advance.
- **Early threshold, both directions, selective barrier:** arriving
  preferences re-evaluate (85 % under the default 80 stays finished when 90
  arrives after the ordinary earlier rewatch progress; the direct-jump
  exception discovered in Step 0 is recorded in Follow-ups); a lower configured threshold
  can trigger on delivery. Hold only the completion loader's `List<int>`
  (the shared cold-preferences barrier, `display_defaults_reads.dart:27`,
  also stalls player defaults awaited before player construction, 2321);
  thresholds above/below 80, exact equality, both policy/threshold arrival
  orders; test-only barriers, no production seam.
- **Failure state:** caught mark failures (flag stays set; resume saves
  then suppressed at 11848 even if persistence failed) vs the **uncaught**
  unawaited rewatch unmark (9548; flag stays spent); hold an unmark across a
  later completion; one movie cleanup branch failing while the other
  succeeds (`Future.wait`). Use the pumping `finish` helper
  (`video_player_environment.dart:307`, P6 stabilization precedent).

Early windows for every moved initializer. Mutation proofs, coverage
matrix, Claude sample.

### Device checklist (end of series)

With no tracker connected: a movie past the configured threshold shows as
watched and leaves Continue Watching; a rewatch below it restores it; an
episode past its threshold is marked finished; "This device" mode marks
locally even with trackers on.

## Phase 8 — PiP, background pause/resume and wakelock

Branch `refactor/vplayer-p8` off the phase-7 merge `491bf1fea`. Evidence
`refactor-evidence/vplayer/p8/`. Line numbers at `491bf1fea`.

**Decision (design review P2): option (b).** On the desktop harness
`_pauseForBackground` returns immediately (10728) and production PiP
callback registration is behind a mobile guard (1581), so a verbatim move
characterized on desktop could not exercise background pause/resume,
callback wiring or their races. A separately reviewed test-only
platform-predicate seam **S2** covers the Dart wiring; native PiP
presentation stays device-pending.

### Order of steps

H (shared fixture hardening, test-only) → S2 (seam checkpoint) → T → 0 →
Claude sample → 0b (k19) → S2b (approved extension; independent review) →
0b (k2; refreshed original/tooling/baseline) → 1 → gate → review → **M1**.

### Step H — shared fixture hardening (test-only)

From the phase-7 review: consolidate fixture support once, without
changing what the race tests exercise. Separate **"wait until the action
entered its held boundary"** from **"await the action's completion"**:
`trakt_snapshots_test.dart:64` deliberately leaves selection pending
behind an open barrier, and `secondary_tracker_driver.dart:140` releases a
held seek only after the earlier helper returns — awaiting completion
there would deadlock or serialize the race. Keep guide-refresh barriers
case-specific with their existing release behaviour; preserve timer
observation and uncaught-error collection; drain pending operations before
resetting transports or closing streams. Proof: test names and assertions
token-identical; **assertions still evaluated while the intended action is
pending** (recorded per race test); representative existing mutation
witnesses re-run and still killed; ≥ 5 serial stress replays of the
tracker/completion/snapshot files under load.

### Step S2 — platform-predicate seam checkpoint (reviewed separately)

A second test-only hook, **separate from S** (`vplayer_seam_proof.py:61`
requires S's exact content; S stays untouched): one facade-level hook
object overriding only the `dart:io Platform` predicates evaluated by (i)
the moved PiP/background methods, (ii) the retained PiP registration guard
(1581) and (iii) the retained predicate sites at 2868, 3922, 4064 and
12694 (subtitle/timeline). Native defaults unchanged; predicate
evaluation order frozen; assert-only installation, release/profile
rejection and the `DEBRIFY_VP_TEST_HOOKS` gate as for S; a source guard;
independent default-path and installation negatives; S's proof still
passes. Moved bodies read the predicates through **live Host predicate
getters** (no destination imports the facade). Tests use the existing
`PipService.debugPlatform`, channel mocks, and mount the real screen
through `IosPipPlayerRoute` for session wiring; `fake_player.dart:190`
gains **distinct controllable handles** (it returns `71` for every player,
which cannot distinguish stale iOS handle callbacks).

**S2b decision (Claude, plan owner, 2026-10-13).** Approve exactly two
additional predicate substitutions: `_initializePlayer`'s
`Platform.isAndroid && !PlatformUtil.isAndroidTvCached` at 2266 and
`_canFallbackExplicitRenderer`'s `isAndroid: Platform.isAndroid` at 3330
(line numbers at S2). Each becomes `VpS2Hooks.isAndroid`, with the other
operands/arguments and their evaluation order unchanged. Same-State player
replacement is available only through Android renderer fallback, which k2
needs while the iOS handle is held; the later player-engine phase needs
this coverage too. Reuse the existing hook/getter/installer unchanged;
extend the seam manifest/proof by one exact patch per declaration and add
independent default/count/order negatives for both sites. Preserve all S2
patches, native default behavior, S proof and the source guard. S2b is a
separate seam extension checkpoint, then **stop for independent review**;
no k2 test, production move, Step-1 CI transition or gate in that checkpoint.

### Moves → `presentation/legacy_video_player/vp_pip_lifecycle.dart`

14 declarations (252 physical lines; destination ≈ 310–330 with Host and
imports, under the 500 cap): the iOS PiP block 10556–10559
(`_iosPipStarting`, `_iosPipDetached`, `_iosPipSession`,
`_lastIosPipPositionSecond` — inert), `_backgroundedAt` (675, inert
nullable; used only by the two moved background methods), `_enterPip`
10562, `_armPipAutoEnter` 10615, `_pushPipState` 10626,
`_onPipModeChanged` 10644, `_restoreIosPipPlayer` 10671, `_onPipAction`
10691, `_pauseForBackground` 10727, `_resumeFromBackground` 10766,
`_syncWakelock` 10805.

**Stay State-owned:** `_isPipActive` (7 reading members, 5 retained),
`_pausedByLifecycle` (5, 4 retained), `_lifecycle` (combines recording and
playback; registers an observer in `initState`). Live Host getters/setters.

**Owner identity:** the 7 moved `PipService.isOwner(this)` occurrences →
`host.pipOwner`, frozen as `Object get pipOwner => _s;`. No moved
`PlayerVisibility` calls; retained registration/visibility/detach keep the
State identity.

**Host (exact, frozen at step T):** player and flags, `setState` (→
`_vpSetState`), `context`/`mounted`, timers/notifiers, recovery/channel
dependencies, the S2 predicate getters, and actions with these exact
signatures: `Future<void> setNativeSubtitleVisibilityForTrack(mk.SubtitleTrack track)`,
`Future<void> goToNextEpisode()`,
`void cancelPendingIptvCatchup({bool hideFeedback = true})`,
`void traktScrobbleSeek(Duration position)` (likewise Simkl/MDBList — the
three tracker calls and `_display.landscapeLocked` are Host projections
registered by exact chain and occurrence). No moved body reads `widget`.

**Retained references (22 occurrences):** session assignment 1019;
lifecycle callbacks 1545/1547 — the `onPause` **closure is retained**
(it first starts recording teardown, then calls the background pause;
only that inner call becomes `_pip.`), `onResume` is a direct tear-off;
PiP registration/readiness callbacks 1587–1589/1594/2229;
position/playing subscriptions 2868–2870/2946/2947; native/subtitle
starting-state reads 3922/4064/12694; parked result handling 5376/5377;
disposal fields 10817–10819 (in place); controls callback 14280.
Listener and session construction/disposal stay at their original sites.

**Scaffolding / CI:** patched State constructor appends `_pip` after
`_completion`; adapter; switch current/self-test and both analyzer inputs
to P8; P1–P7 `--at` incl. P7 `491bf1fea`; protect all 17 earlier
destinations; tests, theme paths and all three theme source-guard lists;
probe receiver-induced async-context diagnostics and preserve `_enterPip`'s
existing diagnostic identities.

### Step 0 — characterization of the original (at S2)

- **Lifecycle:** valid transitions — inactive/hidden do **not** pause;
  paused → background pause (latches `_pausedByLifecycle`; **no resume
  save** — the user-pause save belongs to `_togglePlay`, 12658, so
  pending-save cases come from an existing user action or autosave);
  resumed → resume only if it paused, respecting the sleep latch; the
  retained `onPause` closure's recording teardown runs first.
- **Async boundary matrix (pin effects, errors and actual pending-save
  writes; defects documented separately):** background pause pending when
  resume issues play, then the old pause released; backgrounding during
  renderer replacement or Start Over, incl. no live player yet; sleep
  expiry between pause and resume; support resolution, player-handle
  delivery, native subtitle preparation, PiP entry and restore orientation
  held across replacement, disposal or profile handoff (`_enterPip` 10569
  checks player identity after handle delivery but then awaits subtitle
  preparation; `_restoreIosPipPlayer` 10677 continues platform requests
  across awaits before its final owner check — player/State ownership, not
  profile ownership).
- **Wakelock queued-write semantics** (`player_display_controls.dart:90`
  samples the latest request and independent owners when each queued write
  runs): a held/rejected native toggle, rapid play/pause/dispose,
  buffering, another wake owner keeping the lock, completion with and
  without a playing-false event (EOF alone does not call
  `_syncWakelock(false)`); initial acquisition and the `replacedPip`
  disposal exemption; drain the queue before restoring platform interfaces
  so cleanup cannot supply a release a mutation should expose.
- **PiP (through S2):** auto-enter arming, enter/exit state pushes and
  payloads, mode changes, actions, iOS restore with distinct handles,
  owner identity passed to services; native presentation device-pending.
- Early windows; mutation proofs; coverage matrix with an honest
  device-pending list; Claude sample.

### Device checklist (end of series)

Android: home → PiP auto-enter, PiP play/pause actions, return restores
controls; iOS: PiP start/stop and player restore; background/foreground
pauses and resumes correctly (recording stops on background); screen stays
awake while playing and sleeps when paused.

### Integration milestone M1 (after phase 8 merges)

Full suite, both release builds, and one cross-phase scenario on a single
playback with **local progress ownership plus enabled scrobble targets**
seeded (`tracking_source_policy.dart:133`; otherwise completion stays
disabled): skip-segment seek fans out to all three trackers in order;
speed persists across resume; completion marks at threshold;
end-of-item sleep suppresses advance; lifecycle resume respects the sleep
latch (through S2); a later explicit play and episode reset clear the
latch and completion flags. Mobile coverage as provided by S2; native PiP
device-pending.

## Phase 9 — subtitle engine I: auto-sync, sync overlay and subtitle settings

Branch `refactor/vplayer-p9` off the M1 merge `bd671bd09`. Evidence
`refactor-evidence/vplayer/p9/`. Line numbers at `0df6ccd4e` (phase-8
merge; M1 is test-only) — re-measure by name.

Subtitle work is split over phases 9–11 with one **state-ownership map**
(below) and integration milestone **M2** after phase 11.

### Subtitle state-ownership map (phases 9–11) — revised by the design review

| State | Owner | Notes |
|---|---|---|
| `_subtitleSettings` (1295) | **State** | all six writers move in P9; three retained view methods read it; Host getter/setter |
| `_activeExternalSubtitlePath` (1322) | **State** | 3 reading methods, 2 writers incl. renderer fallback; its **setter** `_setActiveExternalSubtitlePath` moves with P9 (it coordinates auto-sync activation) |
| `_showSyncOverlay` (654) | **State** | 4 readers / 3 writers (overlay actions, build/back, subtitle reset) |
| `_autoSyncPill` (1334, notifier) | **State** (allocation and disposal) | allocation-order rule |
| `_autoSyncPillLastShown` (1341) | **State** | sole reader/writer is retained `build` (13640, fade cache) |
| `_subtitleAutoSyncEnabled`, `_subtitleAutoSync`, `_autoSyncWindowActive`, `_autoSyncPillHold`, `_autoSyncPillPhaseTimer` | **P9 controller** | inert initializers |
| `_subtitleSelectionCorrection` (1109, notifier) | **State** (allocation) | P10 manipulates its value through a Host |
| apply-attempt / diagnostic generation | **State** (decided in phase 10) | |
| addon/Stremio fetch, temp files, priority, track preferences | P11 | |

### Moves → one combined bridge `presentation/legacy_video_player/vp_subtitle_auto_sync.dart`

**One file, one owner (design review P2):** both overlay builders call
`_subtitleAutoSync?.manualOffsetChanged`, an owner-scoped moved field; a
separate helper reaching it through a Host is rejected by
`occurrence_field_bindings.py:150`. The combined file stays well under
400 lines (≈ 260 moved lines). Neither factory has a lexical `context`; the
retained pill builder and existing overlay widgets keep theirs; the local
`externalPath` snapshot and the line picker's live player-position callback
are preserved; no widget wrapper or key change.

**21 moves:** 16 methods — `_installSubtitleAutoSyncForPlayer` 1951,
`_disposeSubtitleAutoSync` 1984, `_applyAutoSubtitleSyncOffset` 1991,
`_showSubtitleAutoSyncNotice` 2009, `_openAutoSyncPillWindow` 2046,
`_showAutoSyncPillResult` 2062, `_hideAutoSyncPill` 2074,
`_setActiveExternalSubtitlePath` 2083, `_loadSubtitleSettings` 5403,
`_onSubtitleStyleChanged` 5549, `_applySubtitleSyncOffset` 5566,
`_resetSubtitleSyncOffset` 5573, `_showSyncOverlayPanel` 5594,
`_hideSyncOverlay` 5602, `_buildSyncOverlay` 5606,
`_buildSliderSyncOverlay` 5631 — and the five auto-sync fields above.

**Host (exact):** `mounted`, `setState` (→ `_vpSetState`), player,
position, playing, audio-passthrough enablement, settings getter/setter,
external-path getter/setter, pill notifier, controls notifier,
overlay-flag setter, TV focus-release action. No widget selectors,
`BuildContext` or owner-identity substitution. The PiP adapter (16406)
forwards to `_setNativeSubtitleVisibilityForTrack`, which is not moved in
P9 — the adapter is unchanged now; its exact facade patch is declared when
that method moves in P10.

**Teardown protocols frozen in place:** renderer replacement calls
`_disposeSubtitleAutoSync` (clears the engine, hides the pill, awaits
disposal before old-player teardown); facade `dispose` cancels the pill
timers and disposes the notifier (10574) and then snapshots/nulls the
engine (10723) — **not** routed through the helper (it would hide an
already-disposed notifier).

**Retained references (33 occurrences):** settings startup 1622;
passthrough suspend/rearm 2130/2147; initial/replacement installation
2430/3439; position/audio subscriptions 2870/2886/2897; replacement
disposal 3404; apply-failure path 4174; enablement write/log 5481/5484;
disposal timers and engine snapshot/clear 10574/10575/10723/10724;
Back/Escape/build 11938/13163/14283; track/menu callbacks 15102, 15111,
15120, 15121, 15257, 15370, 15406, 15458, 15475, 15476; reset/selection/
preference paths 15519, 15524, 15826, 16307. Collaborator constructed after
`_pip`; notifier slot and all disposal statements preserved.

**CI:** current/self-test and both analyzer inputs → P9; P8 `--at
0df6ccd4e`; S/S2/S2b proofs; protect all 18 earlier destinations; new
tests and the destination in the theme manifest, rendered list and all
three source-guard lists.

### Step 0 — characterization of the original

- **Real engine activation (not just a fake instance):** seed auto-sync
  enablement through storage before mount, `native: true`, select a real
  fixture SRT through the existing public subtitle action; drive the
  production path by recording the `af add` filter and its metadata-file
  path and appending deterministic `ametadata` records (or reject the file
  filter and feed the registered `af-metadata/debrify_autosync` observer
  through the real fallback); known speech/cue patterns produce actual
  alignment results. Cover listening, checking, still-listening, synced,
  failed and silent-resync states; the 5 s announce, 2,400 ms result hold
  and 350 ms fade. File I/O and `compute` need completion waits (step H's
  entered/completed distinction; no large blind advances). The desktop
  platform supports auto-sync; S2 does not override
  `supportsSubtitleAutoSync` or the installer's raw Android passthrough
  predicate — state those coverage limits.
- **Teardown and startup windows:** held filter installation/removal and
  alignment across renderer replacement, subtitle changes and disposal
  (cleanup before old-player disposal and output-lease release); selection
  before engine installation (`_setActiveExternalSubtitlePath` stores the
  path with no engine; installation does not activate it; repeating the
  same path returns early); audio-track restarts; passthrough stop/rearm
  order.
- **Settings, corrected:** the timing offset is **session memory only**
  (`subtitle_settings_service.dart:332`, no preference write; it resets on
  subtitle/content change and at startup); style settings persist. Races:
  pending preference initialization across reset and an incoming load;
  pending font lookup while the cached `_prefs` is cleared/replaced
  (profile handoff clears it, `profile_app_lifecycle_participant.dart:88`;
  the service reads the shared field after awaits, `:388`); an
  already-returned snapshot delivered after profile handoff (facade accepts
  on `mounted` only, 5404); overlapping routes resetting the singleton
  offset. Assert rendered settings, native `sub-delay`, migration/style
  writes and propagated errors. Saved overlay callbacks after dismissal,
  content replacement and disposal (they perform engine/pill/native effects
  **before** the mounted check, 5614; `_onSubtitleStyleChanged` checks
  first); native property failures outside the auto-offset catch.
- **TV focus** via `PlatformUtil.debugSetAndroidTvCached`/`debugSetTvOS`:
  first-key delivery, held-repeat, Back dismissal, unchanged overlay element
  identity.
- Early windows; mutation proofs; coverage matrix; Claude sample.

**M2 (after phase 11)** combines auto-sync, manual override during
alignment, apply failure/rollback restoring the previous path,
source/content reset, audio-policy changes, renderer replacement, profile
handoff and the retained PiP visibility caller; preserves both native
properties and the rendered subtitle configuration.

### Device checklist (end of series)

Auto subtitle sync on a mistimed external subtitle (pill announces, result
shows, offset applied); manual sync slider and reset; subtitle style
changes apply live (phone, TV, desktop, tvOS).

## Phase 10 — subtitle engine II: apply, diagnostics and failure rollback

Branch `refactor/vplayer-p10` off the phase-9 merge `5c7b704bd`. Evidence
`refactor-evidence/vplayer/p10/`. Line numbers at `5c7b704bd`.

### Ownership and moves (frozen by the design review)

**Five methods move** → `presentation/legacy_video_player/vp_subtitle_apply.dart`
(≈ 183 existing lines): `_waitForSubtitleTracks` 3889,
`_setNativeSubtitleVisibilityForTrack` 3906,
`_setSubtitleTrackWithDiagnostics` 3924, `_handleSubtitleApplyFailure`
(≈ 3968), `_showSubtitleFailureMessage` 4052.

**State-owned:** `_subtitleDiagnosticGeneration` and
`_activeSubtitleApplyAttempt` (readers/writers span apply, failure,
disposal, content reset, the subscription binder and preference
persistence — two of the attempt's three readers stay outside), and the
`_subtitleSelectionCorrection` notifier (allocation slot). The six
external field occurrences stay unchanged.

**Host (18 names / 21 declarations):** `mounted`, `context`, `setState`
(→ `_vpSetState`), `player`, `addonSubtitleFetchToken`, `isIOS`, `isAndroid`,
`isPipActive`, `iosPipStarting`, `androidVideoRendererMode`,
`selectedStremioSubtitleId` getter/setter, `activeExternalSubtitlePath`
getter, `subtitleSelectionCorrection`, `playerMenuKey`,
`setActiveExternalSubtitlePath(String?)`,
`Future<void> persistTrackChoice(String audio, String subtitle)`, and
getter/setter pairs for both diagnostic fields. `GlobalKey<PlayerMenuPanelState>`
and `ValueNotifier<String?>` identities preserved. Four complete chain
substitutions registered (`registered_occurrence_substitutions.py:17`
precedent): `VpS2Hooks.isIOS`, `VpS2Hooks.isAndroid`, `_pip.iosPipStarting`,
`_subtitleSync.setActiveExternalSubtitlePath` → their Host forms, adapters
reading the live facade; no sibling imports.

**Patched facade adapter:** `_VpPipLifecycleHostAdapter` registered in
`patched_class_projection` (`check_dart_moves.py:148`) with one counted
rewrite of its `setNativeSubtitleVisibilityForTrack` forwarder (16180).

**Retained references (23 executable):** 15 apply calls, 5 failure-message
calls, 1 failure-handler call, 1 track-wait call, 1 PiP-adapter forwarder
(3959/4002/4011 are internal moved-body calls; 8491 is a comment;
10426/10427 are disposal invalidation and 15256/15257 content reset, both
State-owned field writes left unchanged). Diagnostic-log subscription
cancellation and notifier disposal stay in place.

**CI:** current/self-test and both analyzer inputs → P10; P9 `--at
5c7b704bd`; protect all 19 earlier destinations; tests and the destination
in `ci_behavior_tests.txt`, the theme manifest, rendered set and all three
source-guard lists. Collaborator assigned after `_subtitleSync`.

### Step S2c — one-predicate seam extension (reviewed separately)

The Android renderer rejection guard (3930) still uses raw
`Platform.isAndroid`, outside S2/S2b (`vplayer_platform_seam_proof.py:27`).
**Decision:** a separately reviewed **S2c** checkpoint replaces this one
predicate occurrence with `VpS2Hooks.isAndroid` (short-circuit order and
once-only default evaluation preserved; S/S2/S2b proofs retained; the new
site mutation-proven) before step 0. Then characterize bitmap/image
rejection on incompatible renderers, acceptance on `directMediaCodec`, and
the Android-TV exemption (`FakeNativePlayer` records visibility effects;
decoded bitmap rendering stays device-pending).

The S2c ledger is `dev/tool/dart_moves/vplayer_p10_seam.json` (zero moves).
CI's current/self-test and analyzer manifest select that checkpoint, retaining
the P9 diagnostic inventory and adding P9 `--at 5c7b704bd`. This is checkpoint
wiring only; Step T and the production P10 transition follow independent review.

### Step 0 — characterization of the original (at S2c)

- **Apply success:** native track set, visibility per text/bitmap/external,
  generation increment, persisted preference matching the attempt.
- **Correction delivery:** `kUnifiedPlayerMenuEnabled` is constant true, so
  the facade returns before `TracksSheet.show` (14822) — the notifier's only
  listener. Characterize repeated corrections through
  `PlayerMenuPanelState.reconcileSubtitleSelection` (4045), incl. a
  dismissed/reopened menu. Notifier-listener delivery and its null-arm
  purpose are **dormant compatibility behaviour**, protected by the verbatim
  proof; notifier construction, assignments and disposal unchanged.
- **Three distinct late-failure behaviours (pin actual outcomes, add no
  guards, record defects in Follow-ups):** (1) the decoder-log subscription
  reads the *current* attempt (2665; logs carry no generation), so an old
  log arriving after attempt B starts can roll **B** back; (2) a delayed
  exception from A's apply carries A's object and is rejected by the entry
  guard (3986); (3) a rollback of A admitted before B starts has no
  generation recheck after its awaits. Barriers at native visibility, track
  application, rollback visibility/track application and the 50 ms success
  delay, crossed by content reset, profile handoff, disposal and renderer
  replacement. After visibility, apply rereads the live player (3961);
  replacement invalidates subscriptions but not the apply attempt (3252) —
  preserve the captured-platform vs later-live-read distinction.
- **Persistence/completion race matrix:** `_persistTrackChoice` (16071)
  sets `persisted` and assigns `persistenceDone` before writing, swallows
  write errors and completes its completer in `finally`; a second matching
  write can replace the completer; rollback awaits the current one (4036)
  then samples content again. Cover a decoder failure during an optimistic
  write, failed writes still completing, two matching writes released out
  of order, rollback persistence after content/profile changes. Exact
  attempt and completer identities. **Physical writes in both profiles'
  `playback_state_v1`** incl. unrelated entries (track storage reads a map,
  `track_preferences_storage.dart:60`, then `PlaybackStateStore`
  reacquires preferences, `playback_state_store.dart:33` — the same
  cross-profile risk as phase 7's Follow-up). Existing `CompletionDelivery`,
  preference transport doubles and step-H pending-action helpers suffice.
- **S2c cases** above; `_waitForSubtitleTracks` timeout/arrival; early
  windows; mutation proofs; coverage matrix; Claude sample. Feeds M2 (after
  phase 11).

### Device checklist (end of series)

Selecting embedded, addon and external subtitles applies them; a broken
subtitle reverts to the previous one with a message; bitmap (PGS)
subtitles show, and are rejected with a message on an incompatible Android
renderer; the menu reflects the corrected selection.

## Phase 11 — subtitle sources and track preferences

Branch `refactor/vplayer-p11` off the phase-10 merge `7fdf59370`. Evidence
`refactor-evidence/vplayer/p11/`. Line numbers at `7fdf59370`. M2 follows
this phase.

### Three sibling collaborators (design review P2: the two-file split broke the 500-line cap)

Bodies stay whole; each destination's normal formatting is proved at step
T before the split is frozen. No sibling imports; every cross call goes
through the facade. The frozen membership is 15 moved declarations: 13
methods/getters and the two owned fields. Step-T normal-format measurements
are 303/282/412 lines respectively (all ≤500).

| Destination | Declarations | Existing lines |
|---|---|---|
| `vp_subtitle_language_policy.dart` | `_applyDefaultAudioLanguage`, `_audioAllowsAutomaticSubtitles` (getter), `_refreshSubtitleAudioPolicy`, `_applyDefaultSubtitleLanguage`, `_applyForcedSubtitle` | 252 |
| `vp_track_preferences.dart` | `_restoreTrackPreferences` (199), `_persistTrackChoice` | 239 |
| `vp_addon_subtitles.dart` | `_downloadStremioSubtitleToTempFile`, `_applyExternalSubtitleTrack`, `_cleanupTempSubtitleFilesSync`, `_fetchAndMaybeAutoSelectAddonSubtitle`, `_applySubtitleSourcePriority`, `_applySubtitlePriorityUpdate` + fields `_tempSubtitleFiles` (empty set) and `_subtitlePrioritySelectionQueue` (implicit nullable-field constructor — inert) | 326 |

**Stays in the facade:** `_resetSubtitleState` (shared content-reset
orchestrator across phases 9–11), `_findSeriesEpisodeForCurrentIndex`
(retained identity selection, addon discovery, skip adapter),
`_menuSelectEmbeddedSubtitle`, `_menuSelectAddonSubtitle`,
`_menuApplyTrackChange`, `_audioTrackChoiceChanged`, the metadata retry
orchestrator. **State-owned fields:** the fetch token, three cache fields,
selected addon id, embedded/manual/restore-ready flags, audio revision,
injected launch slots, diagnostics, notifiers, UI flags, manual identity
(they span retained menus/identify-title, reset, preferences and addon
selection — the owned-field guard, `occurrence_field_bindings.py:150`,
forbids forwarding a sibling-owned field). `_subtitleSelectedAudio` stays
State-owned, with a live getter/setter in the language Host and its original
reset write retained.

**Hosts (frozen individually at step T):** live widget selectors `String
title` (restore/persistence) and nullable `contentSeason`/`contentEpisode`
(addon identity fallback); action signatures
`applyIptvAudioPreference(int ticket)`,
`waitForSubtitleTracks({required int token})`,
`applyDefaultSubtitleLanguage({bool ignoreSourcePriority = false})`,
`refreshSubtitleAudioPolicy({bool reselect = true})`,
`applySubtitleSourcePriority(List<AddonSubtitleSlot>, int, {bool discoveryReady = true})`;
nullable `isCurrent` callbacks and captured playlist/track-list/
audio-revision/content-token locals preserved. No `BuildContext`,
`setState` or owner identity needed. Three registered P9/P10 chains used
inside moved bodies: external-path setter, track wait and diagnostic apply.
Sync reset remains in the retained reset orchestrator. The exact three Hosts
and their declarations are frozen by the approved
`p11/stepT/host-and-size-proposal.json`.

**Patched facade adapter:** only `_VpSubtitleApplyHostAdapter`
(`patched_class_projection`, one counted rewrite of its persistence
forwarder, 15971); the P9 adapter is unchanged.

**Retained references (28 executable: 22 redirects and six unchanged reset calls):**

| Group | Facade lines |
|---|---|
| Reset | 4848, 8269, 8531, 8740, 8868, 9169 |
| Restore | 2423, 2513, 3332, 8151, 8316, 8366, 9264 |
| Audio-policy refresh | 2748, 14833, 14861 |
| Persistence | 14666, 14819, 14827, 15972 |
| Download / external apply | 14910, 14946 / 14925, 14956 |
| Cleanup (exact dispose/reset positions) | 10221, 15077 |
| Metadata/identify-triggered fetch | 9981, 14507 |

**Language behaviour (corrected terminology):** native selection first,
then English / first real track where applicable; a null addon preference
prefers English; forced selection defaults to English; **no UI-locale
lookup**; ISO aliases, title-based metadata and the distinct `pt-BR` rule.
Restore excludes app-managed addon tracks (15189) and falls through to
default/priority selection. Priority settings are sampled on selection
work; a storage change alone schedules nothing.

**CI:** current/self-test and both analyzer inputs → P11; P10 `--at
7fdf59370`; protect all 20 earlier destinations; all seam proofs; tests and
destinations in `ci_behavior_tests.txt`, theme manifest, rendered set and
the three source-guard lists. Collaborators assigned after `_subtitleApply`.

### Step 0 — characterization of the original

- **Streaming HTTP fixture** (test support only, `MockClient.streaming`
  from the pinned package; no application seam): declared/undeclared
  length limits, the separate 15 s header and body timeouts (15577), body
  errors, client closure; caller-level byte assertions for non-UTF-8
  content, gzip/ZIP extraction, HTML rejection, cache reuse and invalid
  cached files.
- **Cleanup races:** download has no token/mounted/profile guard and can
  finish write → rename → temp-set registration (15603) after dispose
  cleanup (10221) or reset; hold write/rename across reset/disposal and
  inspect final and `.part` files **before** fixture directory deletion;
  overlapping downloads of the same URL/cache stem. Leaks pinned as-is →
  Follow-ups.
- **Discovery/priority concurrency matrix:** final cache publication
  checks only the token (15778; dispose does not bump it); no profile
  identity in fetch or priority validity (15819); the queue coalesces
  same-token updates and lets a newer token proceed. Cover a higher-priority
  addon loading while a lower one succeeds, higher-priority failure and
  fallback, multiple updates during a held download/apply, newer-content
  work proceeding while old work is held, manual/audio changes invalidating
  automatic selection — crossed with outgoing-profile-still-mounted and
  disposal, distinguishing native effects from unobservable retired-State
  cache writes; the service-owned three-attempt retry (500/1,500 ms
  backoffs) outliving the route. Real fixture addon via
  `StremioService.addAddon` (P9 precedent).
- **Restore/default-language races:** restore guards the content token
  but not manual choice, audio revision or profile; after awaiting the
  stored-track language setting (15205) it can apply the captured stored
  track despite a newer manual selection; default audio captures tracks
  before a native-property await then uses the live player (15297); restore
  publishes ready/embedded flags before another awaited policy refresh.
  Held restore/default-audio cases across manual choice, overlapping
  restores, reset, replacement, profile handoff and disposal; IPTV audio
  override ordering preserved.
- **Physical writes:** reuse P10's movie/content cases and add the
  **series** branch (series persistence reads a map and later saves it,
  `track_preferences_storage.dart:12`; the save reacquires active-profile
  preferences, `playback_state_store.dart:33`) — both profiles' physical
  maps incl. unrelated entries, sanitized title keys and fallback titles.
- Early windows; mutation proofs; coverage matrix; Claude sample.

### Device checklist (end of series)

Remembered audio/subtitle choices return on the next episode and session;
default languages pick correctly; forced subtitles show for foreign
dialogue; addon subtitles auto-select by priority; temp subtitle files are
cleaned up.

### Integration milestone M2 (after phase 11 merges)

Parity against a **named, hashed original tree**: the S2c application code
(`a2e034cb3`; it already contains the phase-9 extraction), so M2 parity
covers phases 10–11 against S2c plus phase 9 against its own
characterization; any seam projection needed for a pre-phase-9 baseline is
documented. One scenario with a UTF-8 fixture SRT and the real auto-sync
engine/metadata transport, ordered so manual-choice flags are reset before
automatic audio-policy reselection, then subtitles reselected after
renderer replacement creates a fresh engine: auto-sync + manual override
during alignment, apply failure/rollback restoring the previous path,
source/content reset, audio-policy change, renderer replacement, profile
handoff and the PiP visibility caller. Assert files, native properties,
offset/rendered configuration and profile writes; ≥ 5 mutations spread
across phases 9–11; full suite and both release builds. Native decoding and
PiP presentation stay device-pending.

## Phase 12 — identify title and the subtitle search sheet

Branch `refactor/vplayer-p12` off the M2 merge `6053efabd`. Evidence
`refactor-evidence/vplayer/p12/`. Line numbers at `6053efabd`.

**Eight methods, 643 existing lines,** into two files (sizes proved at
step T; no size exception, no widget-tree change):

| Destination | Members | Lines |
|---|---|---|
| `vp_identify_title.dart` — `VpIdentifyTitle` + Host | `_currentPlaybackTitleForIdentity`, `_identitySearchInitialQuery`, `_subtitleIdentityLabelForSheet`, `_currentSeasonEpisodeForIdentity`, `_identifyTitleAndFetchSubtitles` | ≈ 195 |
| `vp_identify_title_ui.dart` — `VpIdentifyTitleUi`, an **inert presentation helper** with live `mounted`/`context` forwarders + Host | `_buildIdentifyTitleResultTile`, `_showIdentifyTitleSearchSheet` (278), `_requestSeasonEpisodeForIdentity` (98, the episode dialog) | 448 |

**Boundary (frozen):** `VpIdentifyTitle` reaches the sheet and dialog
through **facade Host routing** (`_host.showIdentifyTitleSearchSheet`,
`_host.requestSeasonEpisodeForIdentity` → `_s._identifyUi…`), not a sibling
import. Result-tile taps keep using the **live State context** (13958) —
never `sheetContext` through a new wrapper or parameter; sheet
layout/close actions and episode-dialog actions keep their **lexical
builder contexts**. Search results, tokens, flags, controllers, focus
nodes, the handoff object and `initialSearchStarted` stay in their original
invocation/builder scopes. `setSheetState` and `setDialogState` are
registered with the lexical-setter guard (`occurrence_field_bindings.py:334`)
with real-manifest negatives (each setter or builder context replaced by
the Host's).

**State-owned:** all five manual identity fields incl.
`_manualSubtitleDisplayLabel`. **Host (frozen):** live widget selectors
`title`, `contentTitle`, `contentSeason`, `contentEpisode`;
playlist/index/title and coordinate getters; the required manual/cache/
selection setters; `_vpSetState`; exactly
`Future<void> fetchAndMaybeAutoSelectAddonSubtitle()` forwarding to
`_s._addonSubtitles…` (complete receiver-chain substitution registered).
No player, tracker, skip or preference controller in this Host. Probe
receiver-induced async-context diagnostics (`_host.mounted` may stop
satisfying the lint for `_host.context`).

**Retained references (7):** `_currentPlaybackTitleForIdentity` 14547,
14759; `_subtitleIdentityLabelForSheet` 14721, 15044;
`_currentSeasonEpisodeForIdentity` 12646 (direct-episode prefetch);
`_identifyTitleAndFetchSubtitles` 14720, 15043. Metadata retry calls P11
directly (no reference here). **No P9–P11 adapter needs patching**; the
existing addon manual-field forwarders stay unchanged. Phase-1 helpers
imported: `vpNormalisedContentType`, `vpSubtitleSearchDisplayLabel`,
`vpFilterIdentitySearchResults`, `vpNormalisePosterUrl`,
`vpIdentityMetaSubtitle`, `VpSeasonEpisodeSelection`.

**CI:** current/self-test and both analyzer inputs → P12; P11 `--at
0c2fb62e8`; protect all 23 earlier destinations; all seam proofs; tests and
both destinations in `ci_behavior_tests.txt`, theme manifest, rendered set
and the three source-guard lists. Collaborators assigned after the P11
ones; resource allocations stay inside the action methods.

### Step 0 — characterization of the original

- **Identity effect (corrected):** effective identity getters (1281) read
  channel overrides and widget values, not manual identity; trackers and
  skip use them. Launch identity A → manual subtitle identity B: subtitle
  requests and menu labels adopt B (via the P11 addon Host, 15167) while
  tracker and skip identity stay A. Separately, manual S/E reaching the
  direct-episode prefetch (12646) when earlier coordinate sources are
  absent. Preserve both outcomes.
- **Search submission (no debounce):** typing only cancels focus handoff
  (14186); searches start on submission, the suffix button or the deferred
  initial search; editing does not bump `searchToken`, so an older
  submitted search can publish beneath edited text. Cover typing alone,
  empty submission, repeated submissions, older completion after a newer
  submission, older completion after editing without submission — with
  request counts.
- **Episode dialog:** empty controllers (14336); available coordinates
  **bypass** the dialog (14455) rather than prefill it; empty-field
  validation and cancellation when coordinates are missing.
- **Errors:** ordinary catalog HTTP/JSON failures collapse to empty
  results (`stremio_service.dart:3668`) → classify as empty/partial; drive
  the "Search failed" UI through a real stable-session addon-inventory/
  storage failure. Reuse existing identity tests for filtering/poster
  coverage.
- **Async matrix at the real guards:** completion checks sheet activity,
  State mounted and submitted token (14064) — no profile identity; the
  deferred initial search's first setter runs before those guards;
  resource cleanup only after the modal Future returns. Identification
  commits manual identity and clears subtitle caches **before** fetching
  (14478), never rolls back on failure, and returns after P11 auto-selection
  without another token check (14514); empty-result and catch messages check
  mounted only. Held boundaries at initial-search scheduling, addon-inventory
  lookup, catalog response delivery, sheet selection, episode-dialog
  completion, subtitle discovery and P11 auto-selection, crossed with
  dismissal, content reset, profile handoff and disposal; pin stale results
  and partial commits as-is; distinguish guarded inventory retirement from
  an already-started catalog response under a new profile. Disposal tests
  keep the root Navigator alive long enough to observe controller/focus
  cleanup; step-H entered/completed waits; drain before transport reset.
  Real fixture addon; no application seam.
- **TV:** submitted TV search arms a one-shot handoff (14094); initial and
  suffix-button searches do not — all three paths, focus movement while a
  response is held, first-result activation, repeated directional keys,
  Back during keyboard editing vs route dismissal, restoration to the menu
  through real key events on the rendered menu action (menu focus
  restoration, `player_menu_panel.dart:641`); the episode dialog's solid
  Apply action is its TV autofocus anchor.
- Early windows; mutation proofs; coverage matrix; Claude sample.

### Device checklist (end of series)

Identify title on phone and TV: search, pick a movie, pick a series
episode (dialog only when coordinates are missing); addon subtitles fetch
for the chosen identity; trackers and skip keep the launch identity.

## Follow-ups

- **Phase-11 original late restore (preserved):** a stored-track language read
  resumed after disposal still calls the disposed player's subtitle setter;
  default audio can likewise apply its captured track through the live player
  after manual choice, reset, profile handoff, disposal or renderer replacement.
  Disposal during initial restoration can be followed by `_initializePlayer`
  creating a new six-second autosave timer after dispose already cancelled its
  earlier timers. The characterization asserts that specific leaked timer before
  cancelling only its test-clock handle; application cleanup is unchanged.
- **Phase-11 original file cleanup (preserved):** download has no lifetime guard.
  Write/rename completion after reset/disposal can register a file after cleanup
  ran, leaving the final file behind. Tests inspect final/partial bytes before
  fixture deletion. Overlapping same-stem downloads replace the file in completion
  order and share the set registration.

- **Phase-10 subtitle apply races (S2c original, preserved):** decoder logs read
  the current attempt, so an old log can roll B back. An admitted A rollback
  continues after B/reset/profile/replacement and restores captured ids/path
  without rechecking generation. Apply captures the native platform before its
  await but reads the live player afterward. A manual addon apply can set its
  stale native URI after reset while its outer caller rejects persistence.
- Track preferences re-acquire the active profile after reading a map: A's
  delayed map can overwrite B, including unrelated entries. Rollback waits for
  the newest matching completer; an older physical write finishing last can
  overwrite its correction. Tests inspect both profiles' physical contents.
- A saved menu callback after disposal continues apply/persistence when the
  correction notifier was already null; clearing a non-null correction throws
  in debug mode. The existing disposal resume write can erase the previous
  preference entry in that scenario. Original outcomes are pinned, not fixed.
  Phase-10 evidence and follow-up coverage: `p10/step0/` and the deps matrix.

- **Phase-8 lifecycle/PiP races (original S2, preserved):** backgrounding
  before output creation does not latch the first open; an older held
  background pause can complete after foreground play and win. A user-pause
  save retains its captured physical profile; background pause adds no save.
  A held iOS subtitle preparation can continue PiP entry after State/owner
  loss. After route replacement, its late old handle can replace the service
  handle and an old-handle action can pause the fresh player until fresh entry
  rebases it. Restore continues platform writes across disposal, replacement
  and profile handoff before its final State-owner check. Phase-8 original
  caller tests pin these outcomes; cancellation/ownership fixes are separate.
- A pending MDBList checkpoint fixture exposed an unrelated guide refresh
  rejecting an outgoing profile scope during handoff. Three unchanged original
  isolated replays pass; the fixture now joins public guide refreshes before
  the tested held POST, preserving pending-action assertions. Production stale
  refresh/error handling remains unchanged; see Phase-8 `fixture-note.md`.

- **Cross-profile completion writes (found in phase 7 design review,
  pre-existing, not fixed):** a profile switch between the read and the
  re-acquired write in `EpisodeCompletionStorage.markEpisodeAsFinished` /
  `MovieProgressStorage.markMovieAsFinished`/`unmarkMovieAsFinished` can
  write profile A's map (incl. unrelated entries) into profile B; the
  stale-instance guard does not catch a freshly obtained B instance. Needs a
  captured-scope write path (AGENTS profile rules) and its own tests.

- An early movie jump can cross the default threshold before the completion
  preferences arrive without first spending the rewatch flag below threshold.
  A higher configured threshold then starts an unawaited unmark even though the
  completion guard remains spent; subsequent local resume saves stay suppressed.
  Phase-7 original tests pin this direct-jump ordering as well as the ordinary
  earlier-low-position path that preserves the completed marker. No fix here.

- A source-playlist replacement publishes its rebuilt series cache before URL
  resolution and the later completion reset. A paused position tick can mark the
  unplayed incoming episode if the outgoing index fits the shorter replacement;
  an out-of-range outgoing index instead spends the episode guard without a
  write. Phase-7 original caller tests pin both windows. No fix here.

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

- Trakt initialization awaits the policy before resolving auth ownership: if
  profile handoff completes during that await, the still-mounted outgoing route
  can scrobble with incoming credentials. A handoff during cipher authorization
  instead propagates ResourceAuthorizationException. Phase-5 characterization
  pins both original outcomes; profile/session capture needs a separate fix.
- The Trakt percentage reader captures show identity but only compares the
  shared string binder after storage. A→B→A can accept an older A snapshot over
  a newer A, and ready playlist callers can attempt an outgoing resume seek
  after profile change/disposal. Phase-5 tests retain these original gaps;
  cancellation/generation/profile guards belong to a separate change.

- Simkl loads enablement once; disabling its target while playback remains
  active does not retire its pause/heartbeat/seek/exit sends. MDBList checks
  policy at initialization and likewise continues its existing session.
  Phase-6 characterization preserves both continuations.
- A held Simkl success after route/profile retirement still invalidates the
  global title revision. Its service-owned 409 recovery can retry after the
  route is gone (25 seconds); a changed token rejects the old-profile retry.
  A held MDBList completion after disposal can still publish its playback
  revision; the captured capability rejects a retired profile instead.
- An explicit source-playlist switch can open the incoming episode while an
  outgoing MDBList checkpoint is held. Validation suppresses target switching,
  so the original session can continue checkpointing the outgoing episode.
  Phase 6 records the actual payloads; target handoff needs a separate fix.
- Simkl/MDBList percentage readers share Trakt's string identity binder.
  A→B→A can accept an older A snapshot, and public playlist selections can
  attempt a late resume after profile handoff/disposal. MDBList capability
  capture can also allocate an outgoing session after profile handoff; its
  sends fail authorization while the idle session timer remains until disposal.
  These Phase-6 original outcomes remain separate from this extraction.
- A failed ordinary incoming open retains the incoming MDBList tracker target;
  a failed source preparation can checkpoint an unplayed target before rollback
  restores the outgoing session. Validation release while paused can also leave
  the session's existing playing bit and heartbeat active. Phase-6 tests record
  these original payloads and timers without repairing them.
- A guide-only Simkl/MDBList read can warm its snapshot even when policy masks
  that provider's progress. A later selected-provider resume can use that cached
  value after storage changes; cache freshness is separate follow-up work.


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


### 2026-10-12 — Phase 5 Step T (Trakt tooling checkpoint)

- **Revision/base.** Committed `5d074e762` after approved `fc7196f78`; original application
  re-measured by name at `315028407`: 855 disjoint spans, 12 Trakt moves,
  32 retained occurrences (including the one patched skip-adapter receiver).
- **Proof.** Complete raw/formatted evidence-only P5 splits compare with zero
  differences; 21 live Host readers, five inert false/null initializers,
  eager construction after `_display`, both retained Simkl progress calls and
  all 13 earlier destinations are pinned. Opt-in whole facade-class patch
  projection uses the existing counted-edit/parser core; no old manifest
  behavior changes. Real-config class/receiver/widget/capture negatives pass.
- **Commands/results.** `p5/tooling/checks.json`: all 26 existing Dart manifest
  self-tests, P5 universal/self-compare, P1–P4 merge-revision `--at` and Kotlin
  historical/compiled self-test pass. Format is idempotent; optional comma
  sites recorded, zero introduced formatting diagnostics. Root/strict/probe
  analyzer counts 82/151/84; two mechanical import diagnostics are recorded,
  async-context identities unchanged, earlier inventories preserved. Size and
  architecture pass. Parser audit: 167 unique packages, 144 copied kernels
  deleted; 119 detached packages copied from the already-clean seed.
- **Scope/CI.** Draft only; no production destination, application/pubspec or
  CI/theme changes. P5 CI transition belongs to the Step-1 creation commit.
  Heavy work nice 19; explicit isolated parser flags; serialized suites.
  Evidence `p5/tooling/completion.json` records the resulting commit.


### 2026-10-12 — Phase 5 Step 0 (original Trakt characterization; stop)

- **Revision/base.** Follows Step T `5d074e762`; application re-measured at
  `315028407`, detached under `p5/step0/original`. Resulting Step-0 revision
  and tested tree are recorded in `p5/step0/completion.json`.
- **Harness/behavior.** Isolate-wide delegating HTTP clients, synthetic storage
  sessions, real-cipher and decoded-storage/policy continuation barriers;
  no production seam. 75 new Trakt cases plus two existing skip integration
  cases pass on the original: exact start/pause/stop bodies, 80/81, heartbeat,
  failed-send dedup, launch budget, shared Simkl percent, disabled/validation
  seek handover, held target, early init and show/episode/profile/dispose races.
- **Sweep/proof.** All 12 declarations and 32 retained occurrences classified:
  191 points = 180 assertion kills, ten equivalent, one PiP device-pending.
  A separate player-construction mutation proves early-await disposal. Every
  new case has an assertion kill matching its final case-file hash; invalid,
  comment-only and uncaught-error-only attempts excluded. Original restored.
  Deps tables and `p5/step0/coverage.json` contain cases, points and witnesses.
- **Preserved gaps.** Early policy/profile handoff can use incoming credentials
  for the outgoing route; init/storage failures escape; snapshot readers accept
  old A in A→B→A and ready playlist callers attempt resume after profile/dispose.
  No fixes. Cache null→empty is equivalent through the first identity binder;
  index/scan candidates use original construction invariants, not mount waits.
- **Commands/results.** Nice-19 serialized hook-defined/no-pub controls,
  mutations and `suite_evidence.py run/compare`: 13,047 successes / 13 pre-existing failures / 28 pre-existing load errors / 20 skips,
  **75 passing additions only**, every original identity unchanged.
  Changed test analysis/format/idempotence, unchanged 75 facade diagnostic
  identities, size/architecture and explicit isolated-parser audit PASS.
  Step-T complete-materialization, all Dart/Kotlin self-tests and P1–P4
  historical checks reused; application/tooling inputs are unchanged.
- **Deviation.** One exploratory retry omitted the evidence override; nine
  fixture directories were immediately moved from the old P2 default into
  P5 and that run excluded (`retry-evidence-correction.json`). Accepted runs
  use the explicit P5 root and isolated kernel-clean parser packages.
- **Scope/stop.** Application/pubspec untouched; Trakt only, no production
  moves, bug fixes, allowlisting, device commands, push, merge or branch switch.
  Step 1 will apply P5, register the ten test files and retarget the named
  source guard. Simkl/MDBList extraction is Phase 6. Manual Trakt movie/series
  start/pause/seek/stop, >80 watched, cross-device resume and PiP remain pending.

### 2026-10-12 — Phase 5 Step 0b addendum (independent sample closure)

- **Original/revision.** Follows `1347a5ad8`; detached original at that exact
  revision, application still `315028407`. Resulting addendum revision is
  recorded in `p5/step0b/completion.json`.
- **Sample/closure.** Claude 17/18 killed (94%); h17 was a real gap in the
  State-owned persistable-position dependency. C78/C79 hold a failed ten-minute
  resume at raw 80 ms, then shrink duration to 12.5/10 minutes. Pause, play and
  heartbeat report raw progress, with no automatic watched stop. h17
  assertion-kills both; >=→> kills the exact-80 case. Original restored.
- **Commands/results.** Nice-19 serialized hook-defined/no-pub original
  control and two mutations PASS; changed format/analyzer PASS. Deps sample,
  mutation and supplemental coverage rows updated; 77 new Trakt cases total.
  Clean addendum full-suite baseline follows before Step 1, compared to Step 0
  for exactly two passing additions (`p5/step0b/baseline*`, `suite-delta.json`).
- **Scope.** Test/docs only; no application/pubspec change, seam, fix,
  allowlisting or real network. Existing profile/race gaps remain unchanged.


### 2026-10-12 — Phase 5 Step-1 production creation

- **Revision/base.** Follows addendum `e0772d8d8`; original `315028407`.
  Resulting creation revision/hashes/commands in `p5/step1/completion.json`.
- **Applied.** Twelve Trakt moves, exact 21-member live Host and frozen adapter;
  eager `_trakt` append, all 32 retained occurrences, one counted skip-adapter
  patch and Simkl's two progress forwardings. Shared seek guards/identity,
  persistable-position and analytics/dispose statement order stay State-owned.
  App bytes equal frozen Step-T formatted files; facade 17,394 / destination 294.
- **Commands/results.** Nice-19 P5 current: zero differences. Serialized
  hook-defined/no-pub affected suite: 279 successes, no failure/skip.
  Format, size/architecture and negatives PASS; root/CI comparator 84 / zero
  additions; previous inventory mappings preserved, one frozen unused Trakt
  import warning allowlisted. Broad scan removed 51 unchanged-source/generated
  diagnostics, with no outside additions; variation recorded, no suppression.
- **CI/guards.** Current/self/analyzer→P5; P1–P4 merge-revision history checks;
  ten Trakt files, all theme/source lists registered. Android TV percentage
  guard validates each live reader/capture/rejection and current adapter;
  retained TVMaze, metadata and rewatch checks stay.
- **Baseline/sample.** Clean addendum baseline: 13,049 successes, unchanged
  13 failures / 28 errors / 20 skips; two additions only. Independent sample
  17/18; h17 closed separately on original `1347a5ad8`, no bug fix.
- **Next/constraints.** Clean creation gate, detached source-guard negative
  proof and both release builds follow. Pubspec unchanged, no new seams,
  real API network, device commands, push, merge or switch. Human Trakt/PiP
  checklist and original profile/race gaps remain pending; Phase 6 is later.


### 2026-10-12 — Phase 5 gate fixture scheduling closure (test/docs only)

- **Finding/reproduction.** First clean `edd4d9ca5` suite exposed a missing
  profile snapshot seek before a fixed drain. Identical assertion reproduced
  on original `1347a5ad8` (1/3 fails); moved isolation 3/3 passes. NOTE and
  raw evidence in `p5/gate/profile-repeat`, `profile-stabilization`.
- **Fix/proof.** Await the original public selection Future after releasing
  held storage; all assertions retained. Entire eight-case file original/moved
  3× passes (24 + 24); six original race/missing-row mutations assertion-kill.
  Source restored, format/analyzer pass, application/tooling/pubspec unchanged.
- **Gate.** No failure allowlist or changed expected identity. Step-0b baseline
  reused with original focused validation of this changed fixture; first raw
  failed suite archived. Fresh full gate on clean stabilization commit follows.
  Creation app/tool checks have identical inputs and remain valid. No bug fix.


### 2026-10-12 — Phase 5 clean-tree gate (stop)

- **Revision.** Clean tested `09c43cb56`, creation `edd4d9ca5`; Step-0b baseline
  `e0772d8d8`, application original `315028407`. Gate result/revision and
  artifact/source hashes in `p5/gate/completion.json`.
- **Suite.** Nice-19 serialized hook-defined/no-pub `suite_evidence.py`:
  13,049 successes, unchanged 13 failures / 28 load errors / 20 skips.
  Exact baseline identities/outcomes and official comparison PASS;
  zero added/missing/changed tests, no failure allowlisting.
- **Checks.** All 34 Dart/Kotlin self/current/history commands PASS;
  P5 current/same-revision, historical P1–P4. Root/CI scoped analyzer
  84 / zero additions, prior mappings preserved, CI warning allowlist 47
  nothing new/stale. Exact CI format, 2,998-file size / 140 ratchets,
  architecture and negatives PASS. Broad scan variation/duplicate output is
  archived; unchanged Step-T two-path root command and CI report 84 without
  deduplication or inventory expansion. App/tool compatibility inputs remain
  byte-identical across the test-only stabilization commit.
- **Fixture NOTE.** Original missing-seek timing flake reproduced (1/3);
  real public selection Future now awaited, all assertions retained.
  Original/moved full-file 3× plus six original mutations pass. First raw
  gate archived, fresh full suite rerun, no failure allowlist.
- **Source guard/builds.** Three percentage readers validate live capture
  and identity rejection; wrong reader/adapter forwarding assertion-fails
  on detached creation. Both nice-19 release APK/macOS builds PASS on
  clean tree; logs/artifact/AOT hashes archived, no install/run.
- **Constraints.** Exact frozen 12 moves / 32 references and two app paths;
  eager construction, borrowed guards and per-statement dispose ordering;
  pubspec and all 13 earlier destinations unchanged, trailers and isolated
  parser audit PASS, every original/source-guard mutation restored.
- **Pending/stop.** Human Trakt/PiP movie/series start/pause/seek/stop,
  >80 watched and cross-device resume; original profile/A→B→A/disposal gaps
  retained in Follow-ups. No fix, new seam, real API network, push, merge,
  switch or device command. Phase 5 complete; Phase 6 Simkl/MDBList is later.


### 2026-10-12 — Phase 6 Step T (secondary tracker tooling checkpoint)

- **Revision/base.** Follows approved `1c8ce8e7f`; original application
  re-measured by name at `ea7901ead`: 846 disjoint spans, 24 moved,
  820 retained and two patched declarations; 57 retained substitutions plus
  two counted skip-adapter rewrites give all 59 references. Resulting revision
  and commands are recorded in `p6/tooling/completion.json`.
- **Proof.** Complete raw/formatted evidence-only splits compare with zero
  differences. Eight false/null initializers, 19/15 live Hosts, eager Simkl
  then MDBList construction, existing P5 skip forwarding and both complete
  Trakt-progress chains are frozen. Existing opt-in expression projection
  needs no shared-guard change; guard-only chain/leaf/capture negatives pass.
  All 14 earlier destinations remain protected. Two optional commas inserted,
  none deleted; format idempotent, zero formatting diagnostic changes.
- **Commands/results.** All 33 accepted tooling checks pass: 26 existing
  Dart manifest self-tests, universal P6 self-test/original self-comparison,
  P1–P5 historical merge revisions and complete Kotlin self-test. Root/strict/
  raw/formatted probe diagnostics: 84/153/94/94; prior mappings/maxima retained,
  async-context identities unchanged. Size/architecture and parser audit pass.
  Fresh original full suite: 13,049 successes, 13 failures, 28 load errors,
  20 skips; exact P5 gate identities/outcomes, no allowlist changes.
- **Attempts/scope.** One disposal negative initially used a nonexistent
  textual pattern; corrected whole-statement witness and complete rerun pass.
  A copied driver selected the P5 merge for P4; rejected attempt archived,
  correct P4 `--at 315028407` passes. Application/pubspec unchanged, manifest
  draft, no production destinations or CI/theme changes. CI enables in the
  Step-1 commit creating both P6 scrobblers. Nice 19, isolated parser copies
  with copied kernels deleted, serialized suites; Step 0 continues separately.

### 2026-10-12 — Phase 6 Step 0 (original secondary trackers; stop)

- **Revision/base.** Follows tooling `80a47fa2b`; application re-measured at
  `ea7901ead`, untouched in the main tree. Resulting revision, tested tree,
  source hashes and commands are in `p6/step0/completion.json`. Both P6
  destinations remain absent; the manifest stays draft.
- **Coverage/proofs.** 142 new behavior cases across 21 files, reusing the
  phase-5 isolate-wide transport, synthetic credentials and cipher barrier.
  Real policy/capability/storage completions are held without private State
  access; selections await public `finish()`. Protocols, all-tracker fan-out,
  startup/validation/retirement races, target switches, async percentage readers
  and every early initializer window are pinned through original callers.
  All 24 moved declarations / 59 retained occurrences and 411 AST sites map
  to 319 responsibility points plus one initialization-caller witness:
  301 assertion kills, 15 source-proven equivalences with final-input replays,
  two dormant defensive Simkl start branches and two PiP device references.
  Every addition has a final case-file assertion witness on the detached
  original; no compilation/load/error-only failure earns credit.
- **Commands/results.** Serialized nice-19 original control: 144 cases pass
  (142 additions plus two existing skip integrations). Final full suite with
  `--no-pub --dart-define=DEBRIFY_VP_TEST_HOOKS=true`: 13,191 success / 13
  pre-existing failure / 28 pre-existing load error / 20 skip. Official and
  strict identity comparisons pass: exactly 142 passing additions, zero old
  outcome changes or missing identities. Changed-test analyzer: no issues;
  format: 25 files, zero changes; sizes: 2,998 files / 140 ratchets;
  architecture: 1,666 migrated files pass. Unchanged application/tooling uses
  Step T's 33 accepted manifest/history/self-tests and analyzer inventories.
  Parser isolation/copy-kernel deletion and mutation restoration are audited.
- **Attempts/scope.** Archived first sweep, fixture corrections and closure
  replays. Three invalid dangling-await deletions were replaced by flow-valid
  mutations; an empty-URL probe could not hold the intended await, replaced
  by a real synthetic HTTP barrier. Normal-completion assertions exclude
  error-only witnesses. Final audit refreshed one equivalence replay after
  a reader test changed: all 29 selected cases pass. One fake opt-in permits
  native position before seek acknowledgement; its existing default is
  unchanged. No bug fix, real network, app/pubspec/CI/theme/size-baseline
  change, failure allowlisting, push/merge/switch or device command. Original
  continuation/cache/rollback gaps are in Follow-ups. Manual Simkl/MDBList
  and PiP checklist remains pending. Stop at Step 0; no production moves.

### 2026-10-12 — Phase 6 Step 0b (independent sample survivor audit)

- **Original/sample.** Application `6d2ac75d8` equals `ea7901ead`; Claude's
  independent sample records 18/20 assertion kills (90%). i2/i3 already match
  the Step-0 init-marker and unresolved-episode equivalence proofs.
- **Closure.** Added two original-caller tests: auth resolves while already
  playing, then pause/exit checkpoint exactly 25%; incomplete season-only
  launch rejects pause/heartbeat/seek/EOF/dispose. Detached-original controls
  pass; exact i2/i3 survive. Neighboring pause-marker/whole-guard mutations
  assertion-fail, with logs/patches/test hashes in `p6/step0b/`. Init is called
  once, false enablement prevents earlier pause/stop writes, and no await
  separates enablement from the stamp. The resolver accepts complete pairs
  or bounded parsed episodes; `(season != null, episode == null)` is unreachable.
  Both original statements remain unchanged by the extraction; no forged State
  or direct private-method test is used to manufacture a kill.
- **Evidence/scope.** Broader original control: 146 passing cases (144 new plus
  two existing skip integrations); exact survivors retain equivalent status.
  Full suite: 13,193 success / 13 pre-existing failure / 28 pre-existing load
  error / 20 skip; exactly two passing additions, every old identity/outcome
  unchanged. Analyzer/format pass. Baseline and resulting revision are in
  `p6/step0b/completion.json`. Initial addendum runner accidentally replaced the
  old raw control log; accepted ledger restored exactly, replacement archived
  and hashes/deviation recorded explicitly. Mutation/suite logs remain intact.
  No application/pubspec/bug fix/failure allowlist/production move in this commit.

### 2026-10-12 — Phase 6 Step-1 production creation

- **Revision/scope.** Follows `8c5a962c3`, application original `ea7901ead`;
  resulting revision/check hashes are in `p6/step1/completion.json`. Exactly
  24 moves / 59 retained occurrences; only facade plus two production paths.
  Simkl/MDBList are 283/187 lines, with 19/15 frozen live Hosts, eager inert
  construction in that order, full Trakt-progress chains and the patched skip
  adapter preserving P5 plus two new rewrites. Captured MDBList locals/init
  sequence and every fan-out/disposal position stay unchanged.
- **Transition.** Manifest applied; CI current/self-test/analyzer → P6 with
  P1–P5 historical merges and fetch-depth 0 preserved. Frozen inventory keeps
  all mappings/maxima; five recorded retained-import warnings added to the
  allowlist. All 22 P6 behavior files registered; hooks define retained.
  Theme/source-guard lists include both new destinations. Facade ratchet
  17,394 → 17,087, all historical notes preserved and P6 note appended.
- **Checks.** Current checker rerun after interruption: zero differences,
  all 14 earlier destinations protected; application matches reviewed formatted
  materialization exactly. 167 focused tests pass. Root comparator: 94 scoped,
  zero additions; format idempotent; 3,000-file size / 140 ratchets and
  1,668-file architecture/negatives pass. Validating percentage-reader prefixes
  updated; each new adapter has independent class-local assertions and an
  assertion-failing getter mutation with passing moved control. Originals
  restored. No bug fix, pubspec change, new seam, network or device action.
  The clean-tree gate follows; human checklist remains pending.

### 2026-10-12 — Phase 6 gate fixture scheduling closure (test/docs only)

- **Finding/reproduction.** First clean `dd6fa4016` suite hung during the
  pending-checkpoint profile handoff, cascading into later cases. It is archived
  incomplete, never accepted. Original `6d2ac75d8` reproduces the scheduling
  flake: two isolated passes, one 120-second external deadline; database-lock
  warnings accompany the unpumped fake-zone transaction. NOTE/raw evidence in
  `p6/gate/fixture-note/`.
- **Fix/proof.** Await the same public profile registry operations and incoming
  synthetic-token write through the existing pumping `finish()` helper. All
  21 expectation calls and eight test identities remain unchanged. Entire file
  original/moved 3× passes (24 + 24). Four original mutations assertion-kill:
  MDBList season payload, target-switch await, disposal close, Simkl progress.
  Three supplemental probes survive this eight-case subset; their wider
  Step-0 witnesses are unchanged and no extra kills are claimed.
- **Gate.** Original source restored; test format/analyzer/current checker pass.
  No application/tooling/pubspec change or failure allowance. The same Step-0b
  identity baseline is reused after original focused validation of this fixture.
  All 35 creation-input Dart/history/Kotlin commands have completed successfully
  (Kotlin 597 tests); unchanged application/tool inputs preserve those results.
  A fresh full suite and both release builds follow on the clean fixture commit.
  Resulting revision and test hashes are in `p6/gate/fixture-note/completion.json`.

### 2026-10-12 — Phase 6 clean-tree gate (stop)

- **Revision.** Clean tested `5bb287d72`, creation `dd6fa4016`; Step-0b
  `8c5a962c3`, original application `ea7901ead`. Gate revision, commands,
  input-equality audit, SDK and artifact/evidence hashes are archived in
  `p6/gate/completion.json`. Only the test fixture/docs changed after creation.
- **Suite.** Nice-19 serialized hook-defined/no-pub `suite_evidence.py` full
  run: 13,193 successes, unchanged 13 failures / 28 load errors / 20 skips.
  Official and strict identity/outcome comparisons PASS; zero added, missing,
  changed or newly skipped identities. First incomplete run remains excluded;
  no failure allowance. Fixture closure has original/moved 3× controls and four
  assertion-failing original witnesses, preserving every expectation.
- **Checks.** All 35 Dart/Kotlin self/current/history commands PASS, including
  P6 current/same-revision and P1–P5 at their named merges; Kotlin 597 tests.
  Root and strict-CI analyzer comparators: 94 scoped occurrences, zero additions,
  including infos/multiplicity; global allowlist and comparator negatives pass.
  CI format idempotent; changed test format/analyzer pass. Size 3,000 files /
  140 ratchets and architecture 1,668 migrated files plus negatives PASS.
  Post-fixture current checker, size and architecture also pass. Reused checks
  have identical production/tool/configuration inputs, archived explicitly.
  All manifest invocations use fresh isolated ignored parser packages with
  copied kernels deleted; routing audit archived.
- **Builds.** `nice -n 19 flutter build apk --release --no-pub` and then
  `nice -n 19 flutter build macos --release --no-pub` PASS on the clean tested
  tree. APK, macOS executable and release AOT hashes archived. Flutter 3.44.8 /
  Dart 3.12.2 unchanged; existing macOS plugin SwiftPM notices do not fail build.
- **Stop/pending.** Phase 6 complete at this gate. Human Simkl/MDBList connected
  movie/series start, pause, seek, stop, threshold watched/resume-elsewhere,
  disabled-at-start and disabling-mid-session checks remain pending, along with
  earlier device/PiP checklist items. No device execution, real tracker network,
  pubspec change, bug fix, push, merge, branch switch or later production move.

### 2026-10-13 — Phase 7 Step T (local completion tooling checkpoint)

- **Base/inventory.** Approved `7498196ca`; application re-measured by name at
  `2defa5100`: 828 disjoint declarations, 14 moved / 813 retained / one patched
  constructor, exactly 11 retained occurrences. Six inert initializers (four
  false flags, two references to the storage `static const int` 80), 21 live
  Host getters, eager `_completion` after `_mdblist`; 16 earlier destinations
  protected. Revision/commands/hashes in `p7/tooling/completion.json`.
- **Proof.** Draft manifest, raw and formatted evidence-only complete splits
  compare with zero differences. No optional commas inserted/deleted; formatter
  idempotent and zero introduced diagnostics. Real P7 positive plus ten body/
  scaffolding/order negatives and binding-only selector/capture negatives pass.
  Existing opt-ins suffice; no comparison-core change.
- **Checks.** All 34 required commands PASS: 26 existing Dart manifest
  self-tests, P7 universal/self-original comparison (all 828 classified), six
  named P1–P6 merges and Kotlin self-test (597 tests). Analyzer root/strict/raw/
  formatted counts 94/165/98/98; earlier mappings/maxima retained. The moved
  `empty_catches` identity remains `_markCurrentEpisodeAsFinished`, multiplicity
  one; async-context identities unchanged. Comparator negatives pass. Size
  3,000 / 140 ratchets and architecture 1,668 pass. Isolated parser copies and
  copied-kernel deletion are recorded.
- **Scope/deviation.** First analyzer driver pointed its inventory seed at the
  not-yet-created P7 file; rejected before execution, archived and corrected to
  P6. Original suite baseline reused from P6 gate after exact application/pubspec/
  analysis-config equality at the named P7 base; SDK unchanged. Application and
  pubspec unchanged, no production destination, CI/theme/size-baseline changes.
  CI current/self/analyzer → P7 and test/theme registration enable only in Step 1
  creating `vp_local_completion.dart`. Step 0 follows separately; no moves.

### 2026-10-13 — Phase 7 Step 0 (original local completion; stop)

- **Scope/revision.** Application `2defa5100`, tooling `98bf408f4`; Step-0 revision,
  commands and hashes in `p7/step0/completion.json`. Twelve behavior files / 98
  cases plus the completion driver and opt-in fake frame position (default
  unchanged). All 14 moves and the frozen 11 references are covered through
  original callers; no source-text coverage credit.
- **Proof.** 189 AST sites, 117 canonical points: 114 assertion kills and three
  source-proven equivalences with passing replays. Every addition has a final
  case/support-hash assertion witness; final original 98-case control passes.
  Early windows cover all six initializers and both threshold directions.
  Cross-profile A→B writes, both physical profiles, scoped resume removal,
  disposal, EOF/overlap/fan-out order, partial cleanup and caught/uncaught failures
  are pinned as-is. Coverage, mutation and per-case tables are in the deps report.
- **Findings.** A direct early jump can be unmarked by higher arriving settings;
  a rebuilt source cache can mark an unplayed incoming episode before URL
  resolution/reset, while an invalid old index spends the guard without writing.
  The missing-title return is non-equivalent in that source window. Rejected
  writes can update preference caches; refilling the current cache directly
  proves the failed-rewatch flag stays spent. Follow-ups record these originals;
  no fix.
- **Baseline/checks.** Full suite: 13,291 success / 13 failure / 28 load error /
  20 skip. Official and strict identity comparisons both pass: exactly 98 passing
  additions, every old outcome unchanged, tested tree stable. Fourteen test/support
  files format with zero changes and analyze with no issues; size 3,000 / 140 and
  architecture 1,668 pass. All 34 Step-T commands remain valid (Dart self-tests,
  Kotlin 597 tests, P1–P6 histories and analyzer probe); app/tooling unchanged.
  Parser routing audit: 172 isolated copies, 2,660 invocation/parse records.
- **Deviations/stop.** The first copied runner selected the prior base; its control
  and preflight-rejected sweep are excluded. One nullable-promotion mutant is
  invalid, then replaced by a flow-valid conjunction. Fixture assumptions about
  auto-resume and old/current preference caches are corrected in archived runs.
  Evidence only under `p7/`. Pubspec, application, CI/theme/source guards and size
  baseline unchanged. No production destination, bug fix, real network, push,
  merge, branch switch or device command. Stop here; Step 1 and its gate are later.
  The end-of-series local movie/episode/rewatch/This-device checklist stays pending.

### 2026-10-13 — Phase 7 independent sample and Step-1 production creation

- **Sample.** Claude's accepted original `e62a3a41f` sample kills 20/20 valid
  mutations (100%); no exclusions or addendum. Deps table records each identity
  and original-caller assertion witness. Results/run summary agree; per-mutation
  logs retain tails. Systematic Step-0 matrix stays 114 kills / three equivalences.
- **Move/revision.** Original `2defa5100`; resulting revision, commands and hashes
  in `p7/step1/completion.json`. Fourteen declarations move to the 208-line
  `VpLocalCompletion` with 21 frozen live Host getters. Six inert initializers,
  eager construction after `_mdblist`, local series-playlist snapshot and all 11
  retained statement positions (EOF order/reset/resume reads) are preserved.
  Applied manifest compares with zero differences; all 16 earlier destinations
  protected. Production matches the checked Step-T formatted split exactly.
- **Transition.** CI current/self-test and analyzer manifest **and inventory**
  select P7; P1–P6 histories/fetch-depth 0 retained. Twelve completion behavior
  files registered with the hooks define. Theme surface/rendered/all three source
  guard lists include the new file. Facade ratchet 17,087 → 16,974; no new size
  exception. Two probe-recorded unused retained imports are allowlisted.
- **Checks/scope.** 143 focused completion/theme/source-contract tests pass.
  Scoped analyzer comparator/self-negatives: 98 occurrences, zero additions,
  moved `empty_catches` identity/multiplicity preserved. Format zero changes;
  size 3,001 files / 140 ratchets, architecture 1,669 and its negatives pass.
  No behavior/test assertion change, bug fix, pubspec change, real network,
  push/merge/switch or device execution. Clean-tree gate follows; end-of-series
  local movie/episode/rewatch/This-device and earlier device checklists pending.

### 2026-10-13 — Phase 7 gate fixture closure (test/docs only)

- **Reproduction.** First clean `cc430295d` suite completed and is rejected:
  exactly one changed identity, Simkl suspended episode snapshot (600 s instead
  of 360 s); all 98 completion cases pass. Unmodified original `2defa5100`
  reproduces it on isolated run two, after one passing run. No failure allowance.
- **Cause/fix.** Guide background refresh can persist the synthetic empty Simkl
  response over the seeded snapshot; an original diagnostic trace observes the
  concurrent player reader loading `{}`. Hold guide HTTP refreshes with the
  existing completer until race assertions finish, then release the existing
  404/cleanup path. Production is untouched. Earlier wait/reader-ordinal
  candidates failed and remain excluded; diagnostic sources restored.
- **Proof/checks.** Entire 16-case file original/moved 3× passes (48 + 48), plus
  restored final original control. Isolated AST proof preserves all 19 expectation
  calls and test-name tokens. Simkl and MDBList percent+1 mutations on the original
  assertion-fail against unchanged duration expectations; both sources restored.
  Test format/analyzer pass. The first token-audit attempt omitted ownership
  output and rejected before mutation execution; corrected with a fresh parser.
  Commands/hashes/revision and NOTE in `p7/gate/fixture-note/`.
- **Gate.** Same accepted Step-0 identity baseline retained after original fixture
  validation. Fresh clean full suite/builds follow this test/docs commit; manifest
  matrix continues with unchanged production/tool/configuration inputs. Human
  device checklist pending; no bug fix, pubspec change or device execution.

### 2026-10-13 — Phase 7 clean-tree gate (stop)

- **Revision/evidence.** Production `cc430295d`, original-proven fixture
  `dd2899773` (clean tested tree), Step-0 baseline `e62a3a41f`, original application
  `2defa5100`. Resulting gate revision, commands, SDK, tree/input equality,
  parser routing and artifact/evidence hashes: `p7/gate/completion.json`.
- **Suite.** Nice-19 serialized hook-defined/no-pub full suite: 13,291 success /
  unchanged 13 failure / 28 load error / 20 skip. Official and strict comparisons
  PASS: zero added, missing, changed or newly skipped identities. First completed
  failed gate is excluded. Original-proven guide-refresh fixture preserves all
  19 expectation calls and names; 16 behavior cases original/moved 3× (48 + 48),
  final restored original control and two assertion-killing original mutations.
  Fixture-note counts corrected to exclude loading/setup events; no new allowance.
- **Checks.** All 36 manifest/Kotlin commands PASS: 26 existing Dart manifests,
  P7 self/current/same-revision and P1–P6 at the named merges; Kotlin 597 tests.
  Post-fixture P7 current guard also PASS. Production/tool/configuration inputs
  unchanged by the fixture closure, audited. CI format idempotent; root/strict-CI
  scoped comparator: 98 occurrences, zero additions, including moved
  `empty_catches` identity/multiplicity. Global 54-warning allowlist, comparator
  negatives, size 3,001 files / 140 ratchets and architecture 1,669 / negatives
  PASS. Isolated CLI parser packages and copied-kernel deletion are archived.
- **Builds.** Clean `nice -n 19 flutter build apk --release --no-pub` and then
  `flutter build macos --release --no-pub` both PASS. APK/macOS executable/AOT
  hashes archived. Same Flutter 3.44.8 / Dart 3.12.2; existing plugin SwiftPM
  notices do not fail the build.
- **Stop/pending.** Phase 7 stops at this gate. Human local movie/episode threshold,
  rewatch/Continue Watching and This-device-with-trackers checks remain pending,
  alongside earlier device/PiP items. Original cross-profile completion writes
  remain preserved and documented in Follow-ups. No bug fix, pubspec change,
  real tracker network, device execution, push, merge, branch switch or later move.

2026-10-13 — **Phase 7 independent review (Codex `vp-rev7`): no P1/P2 — "No P1s".**
P3s: (1) harden the shared asynchronous fixtures once (action-completion
waits, guide-refresh barriers, cleanup in shared support; stress-replay with
unchanged assertions) — scheduled as test-only step H at the start of phase
8, before milestone M1; (2) size summaries corrected to 3,001 files. Claude
sample 20/20. Merged.

### 2026-10-13 — Phase 8 Step H (shared fixture hardening; test-only)

- **Revision/scope.** Input `e42e152a4`, original application `491bf1fea`;
  test-only shared action lifetimes distinguish held-boundary entry from
  completion, retain case-specific guide barriers, and drain before stream/
  transport cleanup. Timer observation and uncaught-error collection unchanged.
- **Proof.** Existing names/expectation tokens preserved. Original detached
  assertion audit records the intended pending action per race, including held
  incoming open, held seek, snapshots, credentials and cross-profile completion.
  Five serial nice-19 stress replays under CPU load: 313 cases × 5 PASS; loading
  events excluded. Five representative original mutations assertion-killed;
  restored control PASS. Tables/commands/logs: `p8/h/` and deps Step H.
- **Checks/deviations.** Test analyzer (zero issues), format, exhaustive P7
  current guard, size/architecture and diff PASS. Explicit `void` fixes an
  intermediate inference-only warning. One preliminary run used the old P2
  runtime fallback; excluded and its 55 case directories relocated to P8 by
  birth-time ledger. Fallback corrected; all accepted runs explicitly use P8.
  Application/pubspec unchanged; no T, Step 0 or production move. S2 follows
  separately and then stops for independent review.

### 2026-10-13 — Phase 8 S2 (second characterization checkpoint; stop)

- **Revision/scope.** H `ef663d89d`, original `491bf1fea`. Separate `VpS2Hooks`
  covers exactly 15 predicates in nine declarations, native defaults/live
  callbacks and original short-circuit order. S is untouched and its proof
  passes. Fake players gain distinct stable, held/failed controllable handles.
- **Proof/checks.** Exhaustive 817-span checkpoint (nine patched declarations, frozen hook,
  zero moves), current + P7 historical guard, 13 independent source/default/
  installer negatives PASS. Five actual-body mode controls (debug flag/no flag,
  assert-disabled, profile, compiled release) PASS; seven runtime mutations fail
  their checks. Hook-defined focused 40 cases and no-flag seven cases PASS.
  Analyzer: unchanged diagnostic identities, 98 occurrences; raw/final format identity proof
  PASS, two optional commas, idempotence; size/architecture/diff PASS. `p8/s2/`.
- **Integration.** CI/source reader select the S2 checkpoint; current/self-test
  and analyzer manifest use it with unchanged P7 inventory, P7 `--at 491bf1fea`
  added. Applied owners sort after same-phase seams (old S-only ordering has an
  assertion witness). Guard test registered; existing harness flag retained.
  Dated facade allowance +30 lines (16,974 → 17,004); no feature file created.
- **Notes/stop.** Longer names produced format-only brace infos; final compact
  hook preserves original guard formatting without analyzer allowance changes. Rejected
  filename/raw-root command attempts retained and replaced with complete runs.
  Pubspec and other application files unchanged. Native PiP device-pending;
  no T, Step 0, production moves, push, merge, branch switch or device action.
  Stop here for S2 independent review, as approved by the Phase-8 resolution.

2026-10-13 — **Phase 8 independent H/S2 review (`vp-rev8s2`): no P1/P2/P3.**
H `ef663d89d` and S2 `21b19c944` accepted. S2 is the ORIGINAL for Phase-8
behavior and mutation proofs; the phase-7 merge remains the historical merge
checkpoint. Step T/0 proceed without production moves.

### 2026-10-13 — Phase 8 Step T (tooling checkpoint; no production move)

- **Revision/base.** Follows independently accepted S2 `21b19c944` (behavior
  ORIGINAL). Full draft materialization: 14 moves, 22 retained occurrences,
  seven State-owner projections, 33 frozen Host members, 17 earlier files.
  State constructor appends `_pip` after completion; onPause closure/order
  preserved. Initializers separately inert; exact live predicate/tracker/display
  chains registered. Application and pubspec remain exactly S2.
- **Tooling.** Captured `backgroundedAt` needs two explicit owned-field `this`
  qualifications. New opt-in validates the exact field/owner/count while other
  owner-identity `this` remains rejected; missing/wrong opt-in and binding-only
  capture/chain negatives PASS, existing manifests unchanged.
- **Checks.** All 26 existing Dart manifest self-tests, P1–P7 at named merges,
  Kotlin (34 commands), universal Dart self-test/real P8 configuration, S/S2
  proofs PASS. Root/strict/probe analyzer 98/170/99; one receiver-induced async
  context info in `_enterPip` recorded by identity; earlier mappings preserved.
  Raw/formatted token comparison and idempotence PASS; zero format diagnostics.
  Size/architecture/diff PASS. Nice-19, isolated parser routing: `p8/tooling/`.
- **Next.** Step 0 at S2, no production moves or CI transition. Pristine S2
  suite has one guide/profile race also observed on the original; excluded
  pending replay/fixture closure, never allowlisted. `p8/step0/` records it.

### 2026-10-13 — Phase 8 Step 0 (original characterization checkpoint; stop)

- **Revision/base.** This Step-0 checkpoint follows Step T `fcdfa03eb`;
  application ORIGINAL is independently accepted S2 `21b19c944`, not the
  phase-7 merge. H/S2 review `vp-rev8s2` found no P1/P2/P3. Application and
  pubspec are byte-identical to S2; no production moves or CI transition.
- **Coverage.** Ten registered behavior files add 90 passing cases through
  real screen callbacks, lifecycle transitions, iOS route/session, distinct
  handles, channels, player/storage transports and timers. The deps report
  records all 14 moved declarations and 22 retained occurrences: 327 AST
  sites grouped into 167 canonical points, **145 assertion kills / 12 proven
  equivalences / 10 device-pending**. Every new case has an assertion-failing
  original mutation witness; four additional wakelock/fixture witnesses pass
  the same kill criterion. Invalid, interrupted and error-only runs get no
  credit. Native recording order, renderer recreation and actual native PiP/
  power behavior remain on the device checklist.
- **Commands/results.** Serialized nice-19 original controls/mutations use
  `flutter test --concurrency=1 --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true --reporter=json`; exact file/name
  selectors and input hashes are in `p8/step0/mutation-results.json`.
  `suite_evidence.py run vplayer/p8/step0/final-suite --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true` completed; official `compare` and
  strict identity comparison PASS against the completed stabilized original:
  **13,386 successes / 13 failures / 28 load errors / 20 skips**, exactly
  90 passing additions, no changed/missing/fixed/newly skipped old identity.
  Targeted Dart format/analyze, size/architecture and diff checks PASS.
  Step-T historical, self-test, seam and analyzer evidence remains applicable;
  no tooling/application change. Evidence: `<git-common-dir>/refactor-evidence/
  vplayer/p8/step0/`; matrix, mutation table and commands in the deps report.
- **Deviations/findings.** A complete pristine original suite exposed the
  unrelated guide/profile race. Three unchanged isolated replays pass;
  joining public guide refreshes before its held POST stabilizes only the
  fixture. All old names/assertions retained, independent protocol mutation
  killed; no allowlist. Failed development controls and copy/promotion errors
  are archived and uncredited. Final full-suite inputs stayed stable during
  execution; afterward only a duplicate analyzer-ignore comment was removed,
  with exact byte-delta proof and clean analysis. Existing early-background,
  late-pause and stale PiP/restore outcomes are recorded in Follow-ups. No fix,
  new seam, real network, build/run/install, device command, push, merge or
  branch switch. Stop before Claude's sample and production moves.

### 2026-10-13 — Phase 8 k19 addendum; k2 prerequisite (test/docs only)

- **Revision/base.** Follows accepted Step 0 `6785b4985`; application remains
  byte-identical to S2 `21b19c944`. Claude's independent original sample killed
  18/20 (90%); recorded in the deps table with both survivors distinguished.
- **k19 closed.** Public lifecycle callbacks on a live IPTV channel after five
  real seconds now pin in-buffer play, one existing open, no rejoin diagnostic
  and the unchanged channel. The existing >30-second retune case is retained.
  New case passes on detached original `6785b4985`; 30 → 3 seconds produces an
  assertion failure there (`p8/step0b/k19-results.json`). This strengthens the
  existing threshold point with its lower-bound literal variant; 91 Phase-8
  behavior cases now have original assertion witnesses.
- **Checks.** Nice-19 serialized projection control, detached original control
  and mutation use `flutter test --concurrency=1 --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true --reporter=json`. Exact commands and
  hashes archived. Format/analyze/diff PASS. Fresh
  `suite_evidence.py run vplayer/p8/step0b/final-suite --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true` completed; official and strict
  comparison versus Step 0 PASS: **13,387 success / 13 failure / 28 load error /
  20 skip**, exactly one passing addition, no changed/missing/fixed/new skip.
  Inputs stable; no new flake or allowance.
- **k2 pending; no Step 1/gate.** Same-State replacement only occurs in the
  Android renderer fallback, whose eligibility and settings load use real
  `Platform.isAndroid` outside the approved S2 sites. Route replacement changes
  State/owner and cannot kill this player-identity mutation. Reachability proof
  and an un-applied two-site S2 prerequisite patch are under `p8/step0b/`.
  A direction question remains pending: separately reviewed seam extension,
  or explicit device-pending classification before continuing. No private
  State call, extra initialization, source-text behavior test or application
  change manufactures the missing condition. No bug fix, pubspec change,
  real network, build/run/install, device command, push, merge or branch switch.

### 2026-10-13 — S2b seam extension checkpoint (stop for independent review)

- **Revision/decision.** Follows `652def541`. Claude, plan owner, approved
  exactly the two Android renderer guards so k2 can exercise replacement in
  the same State and the later player-engine phase can reuse the coverage.
  Decision/rationale recorded in Characterization harness and Phase 8.
- **Change/proof.** Only `_initializePlayer`'s renderer condition and
  `_canFallbackExplicitRenderer`'s Android argument now read
  `VpS2Hooks.isAndroid`. Existing hook/getters/installer and all nine S2
  declaration patches stay frozen; no new installer. Native predicate once,
  short-circuit/argument order and all other application bytes preserved.
  Extended seam ledger: 817 spans, 11 patched declarations, 13 counted patches,
  17 occurrences. Ten new independent site negatives, 23 total, PASS.
- **Commands/results.** Nice-19 `vplayer_seam_proof.py --self-test`,
  `vplayer_platform_seam_proof.py --self-test`, current seam
  `check_dart_moves.py` and historical `--at 21b19c944` PASS; every command
  uses an isolated copied `--parser-package` under `.dart_tool/vplayer_parser/`
  with copied kernels removed. Serialized `suite_evidence.py run` on the
  existing S/S2 guard files with `--no-pub --concurrency=1` and
  `--dart-define=DEBRIFY_VP_TEST_HOOKS=true/false`: 7/7 PASS in each mode.
  Scoped root analysis: 98 diagnostics, zero new identities/counts;
  analyzer comparator/self-tests and guard-test analysis PASS. Dart format /
  idempotence, size, architecture and diff PASS. Commands, JSONL, input/SDK
  metadata, exact delta and proof outputs: `p8/s2b/`.
- **Deviations/stop.** Two rejected manifest drafts (broad matching and
  incomplete patch metadata) archived without passing credit; exact scoped
  patches corrected. No k2 characterization, production move, Step-1 CI
  transition or gate. Application diff is the two approved predicates;
  pubspec unchanged. No bug fix, real network, run/install/device action,
  push, merge or branch switch. Stop for S2b independent review. After
  acceptance, refresh the Phase-8 draft/probe against S2b before continuing;
  prior S2 materialization is not claimed as current evidence.

### 2026-10-13 — S2b independent review and Phase-8 k2 closure

- **Accepted original.** Fresh review `vp-rev8s2b`: no P1/P2/P3. S2b
  `866cbaf03` is the ORIGINAL for further Phase-8 behavior and mutation proofs.
  Existing k19 closure `652def541` remains recorded; no production move here.
- **k2.** Public controls start iOS-style entry with a held old handle; the
  original player error subscription triggers Android renderer fallback via
  S2/S2b. Same State and PiP owner, two distinct players/handles, old disposal
  and the Automatic preference are asserted. Releasing the old handle produces
  no subtitle preparation on either instance, no state push and no native
  entry. Unmodified original passes; removing the post-handle identity guard
  assertion-fails in the detached S2b checkout (`p8/k2/results.json`).
- **Reachability refresh.** S2b also opens the other previously deferred
  renderer paths. Four additional public-caller cases pin no-player entry,
  renderer-gap pause/latch, created-player pause, foreground during held audio,
  first live in-buffer resume and consumed long-absence timestamps. All new
  cases have original assertion witnesses. The final player check is killed
  by the held-handle case too. Remaining resume-created/mounted guard is
  source-proven redundant for registered lifecycle dispatch, with a complete
  original replay; preserved in production. Updated matrix: 154 canonical
  assertion kills / 13 equivalences, 167 points; native presentation/recording/
  power checks remain device-pending. 96 Phase-8 behavior cases in 11 files.
- **Tooling.** Draft P8 manifest re-measured/materialized against S2b: 14 moves,
  22 retained occurrences, seven owners, frozen scaffolding and all earlier
  destinations. Optional-comma/idempotence proof PASS. Refreshed analyzer
  root/strict/probe 98/170/99; earlier identity mappings retained. Evidence
  `p8/refresh/`; draft only, no production change. New renderer test registered
  in the existing harness-flag CI list.
- **Validation/deviations.** Nice-19 serialized controls/mutations use
  `--no-pub --concurrency=1 --dart-define=DEBRIFY_VP_TEST_HOOKS=true`. Exact
  commands, patches, assertions and hashes under `p8/k2/`. Test analysis/format
  PASS. Initial zero-position startup stalled before reaching the scenario;
  that interrupted run gets no credit. Initial detached setup lacked its
  ignored package graph; corrected without pubspec changes. Initial renderer
  controls over-counted Video pauses and included unrelated decoder reads;
  final assertions pin the observed renderer-gap behavior and subtitle writes.
  All rejected/development runs archived. Full additions-only baseline follows
  before Step 1. No bug fix, real network, run/install/device, push/merge/switch.

### 2026-10-13 — Phase 8 addendum baseline and Step 1 creation

- **Revisions/base.** Addendum `13df9a261`, behavior ORIGINAL S2b `866cbaf03`.
  Complete `p8/k2/baseline.jsonl`: 13,392 success / 13 failure / 28 load error /
  20 skip. Official and strict comparisons versus the k19 baseline PASS:
  exactly five passing additions, no changed/missing/fixed/newly skipped old
  identity. Stable clean-tree inputs; no allowance or flaky fixture change.
- **Production move.** `VpPipLifecycle` + narrow Host, 318 lines, owns exactly
  the 14 frozen declarations. Eager State constructor appends `_pip` after
  completion, all fields/constructor inert. Frozen adapter forwards live S2
  predicates, trackers and landscape state; seven owner substitutions use the
  State. All 22 retained occurrences stay in place, including only the inner
  call in the recording-first onPause closure and each disposal statement.
  Current checker: zero differences; previous 17 destinations protected.
- **CI/theme.** Current/self-test and both analyzer inputs now P8; P1–P7
  named `--at` gates retained, S proof added explicitly, S2/S2b proof enabled.
  Existing `lib/features` format/analyze lists include the new file. Eleven
  behavior files registered with harness flag. Theme manifest/rendered set
  and all three source-guard lists extended. No moved declaration has another
  direct source-test anchor requiring retarget; source reader validates the
  applied ownership ledger. Facade size baseline 17,004 → 16,829.
- **Checks.** Nice-19 current-tree move comparison, optional-comma/idempotence
  proof, format and architecture PASS. Serialized focused PiP/renderer/wake,
  seam and theme guards: 111/111 PASS on moved code (`p8/step1/`). Original
  controls/mutation witnesses remain archived. Probe/root identity inventory
  preserved; three destination infos are recorded, no new warning allowance.
  Full clean-tree gate follows; no gate result claimed in this creation commit.
  No bug fix, pubspec change, real network, run/install/device, push/merge/switch.

### 2026-10-13 — Phase 8 clean-tree gate

- **Revision/evidence.** Production `901d08edd`; original S2b `866cbaf03`,
  addendum baseline `13df9a261`. Complete gate evidence `p8/gate/`:
  `completion.json`, `suite-strict.json`, `checks-results.json`, analyzer and
  build results. Checks ran on the clean production tree; gate changes are
  documentation and restored size-baseline provenance comments only.
- **Suite parity.** Nice-19 serialized full suite with `--no-pub` and
  `--dart-define=DEBRIFY_VP_TEST_HOOKS=true`: 13,392 success / 13 failure /
  28 load error / 20 skip. `suite_evidence.py compare --against
  p8/k2/baseline.jsonl` and strict identity comparison PASS: zero changed,
  added or missing identities; SDK equal, tested tree stable. The failures
  and load errors are the original baseline set. No flake or test fix.
- **Static/mechanical checks.** Format 124 files, zero changes; size and
  architecture plus their real negative fixtures PASS. Full CI analyzer
  scope: 494 diagnostics, shared allowlist's 54 pre-existing warnings,
  nothing new; its 99 video-player diagnostics exactly match the scoped
  declaration comparator (zero additions, negative self-tests PASS).
  All 38 move/seam jobs PASS: 26 existing Dart-manifest self-tests, P8
  exhaustive self-test and current comparison, Kotlin self-test, P1–P7 at
  their named merges, S and S2/S2b proofs. Every manifest invocation uses
  an isolated copied parser package with copied kernels deleted.
- **Builds/checklist.** `flutter build apk --release --no-pub` and
  `flutter build macos --release --no-pub`, nice-19, both PASS; artifacts
  hashed in `completion.json`. Android Home/auto-enter/actions/restored
  controls, iOS native PiP start/stop/player restore, real recording stop
  on background and native wake/decoder power behavior remain device-pending.
  M1 is after this phase merges and was not executed at this checkpoint.
- **Deviations/stop.** Supplemental global-allowlist attempts using a scoped
  log and an unexpanded CI wildcard were invalid inputs, archived uncredited;
  corrected complete CI scope passes. The shrink-only size updater dropped
  dated comments, restored here with the P8 ratchet note. No application
  fix, allowance, pubspec change, live application request, run/install/device,
  push/merge/branch switch. Stop for Phase-8 independent review.

### 2026-10-13 — Integration milestone M1 (after Phase 8 merge)

- **Inputs/scope.** Merged application `0df6ccd4e`; original application
  `13df9a261` lib/ in detached `m1/original/`. One new 409-line scenario,
  `video_player_m1_integration_test.dart`, registered with the existing harness
  flag in `ci_behavior_tests.txt`. No production/dependency change.
- **Scenario/parity.** One State/player, two episodes; explicit local progress
  ownership plus all three synthetic-credential tracker targets. Public skip
  action pins Trakt→Simkl→MDBList timer-owner order separately from asynchronous
  HTTP delivery and checks protocol/identity/progress. A real speed save feeds
  incoming resume against a different outgoing rate. Threshold/one-shot local
  marks, EOF sleep suppression, S2 lifecycle sleep-latch precedence, explicit
  play and independent episode-reset latch clearing all assert observable
  calls/storage. Same final file passes original and merged; eight valid
  original mutations across phases 2–8 assertion-killed, restored control PASS.
  Table/patches/logs `m1/mutations/`, final SHA/parity `scenario/parity.json`.
- **Fixture stabilization.** The first suite attempt exposed a pre-existing
  Simkl snapshot/profile SQLite lock, reproduced on unmodified original (same
  warning/hang; terminated after 240s). Test-owned `incomingProfile` now uses
  Step-H `finish()` for three registry waits, preserving ordering/arguments and
  all test bodies/assertions byte-for-byte. Five serial final original replay
  groups: 34 cases × 5 PASS under checker load. Fixture analysis clean. Failed
  and early interrupted attempts archived uncredited; final suite restarted.
- **Gate.** Complete `m1/gate/`: suite by identity against Phase-8 gate:
  13,393 success / 13 failure / 28 load error / 20 skip; exactly one passing
  addition (M1), zero changed/missing/fixed/newly skipped identities. SDK equal,
  tested tree stable. Analyzer 99 scoped diagnostics / zero additions; shared
  54-warning allowlist unchanged. Format, size/architecture and real negatives,
  all 38 Dart/Kotlin/history/seam jobs and APK/macOS release builds PASS.
  Commands/results and artifact hashes in `completion.json`; every manifest
  uses an isolated copied parser package with copied kernels deleted.
- **Limitations/stop.** M1 automated milestone complete. Native Android/iOS PiP
  presentation/restoration, real recording teardown and wake/decoder power
  behavior remain device-pending. No app bug fix, allowance, pubspec change,
  live application request, run/install/device, push/merge/branch switch. Stop.

### 2026-10-13 — Phase 9 Step T (subtitle engine I)

- **Input/checkpoint.** Base `bd671bd09`, design parent `6e9b187c8`;
  evidence `p9/stepT/completion.json`. Application and pubspec unchanged.
  The evidence-only split classifies all 807 original spans, moves exactly
  21 declarations into one combined bridge, qualifies all 33 retained
  occurrences and protects all 18 earlier destinations. Constructor appends
  the inert collaborator after PiP; five false/null initializers and the exact
  live Host/adapter are frozen. Both teardown protocols remain in place.
- **Commands/results.** Nice-19 `draft_vplayer_subtitle_sync_moves.py
  --parser-package <isolated> --probe <p9/stepT/probe>` compares with zero
  differences. All 38 mechanical jobs PASS: every existing Dart-manifest
  self-test, complete P9 self-test/all-retained self-compare, Kotlin's 597
  self-tests, P1–P8 at their named merges and S/S2/S2b proofs. Copied parser
  kernels deleted; isolated packages and commands recorded.
- **Analyzer/format.** Original root/strict/probe 99/171/104 diagnostics;
  earlier identities preserved, no new async-context identity. The probe
  records three mechanically unused facade imports and two destination
  directive infos; no allowance or production import edit in T. Formatted
  probe also 104, identical identities: zero formatting additions. AST comma
  sites and idempotence archived. Real negatives cover setter targets, live
  reads/snapshots, notifier ownership, constructor inertness and teardown.
- **Deviation/next.** The first P9 self-test stopped on a materialized scaffold
  spacing mismatch in a fixture needle; corrected matching, complete self-test
  rerun PASS. No comparator relaxation. CI remains on applied P8 until the
  P9 production creation commit. Step 0 characterizes the original next.


### 2026-10-13 — Phase 9 Step 0 (complete; stop before production moves)

- **Revision/input.** Follows tooling checkpoint `9d36d7c83`; original
  application re-measured at `bd671bd09`. Evidence `p9/step0/completion.json`
  and its commit receipt record the final revision. Library and pubspec files
  remain byte-identical to the original. No seam extension, production move,
  CI transition, ratchet change or release build in Step 0.
- **Characterization.** Six new suites/support driver provide 70 original-caller
  cases: real SRT/metadata/compute activation, every pill phase and exact
  5s/2400ms/350ms timing, held install/remove/alignment and renderer teardown,
  early no-engine/null-model/cold-window paths, session-only timing and actual
  style/migration writes, profile/prefs/font races, saved callbacks, native
  failures and TV first-key/repeats/Back/element identity. H support is reused
  unchanged. A rollback held across disposal observes the nulled engine before
  its mounted UI guard; no lifecycle/profile bug is fixed.
- **Systematic proof.** 21 declarations /190 AST sites /170 canonical candidates:
  151 assertion-killed, 12 source-audited equivalents replayed, two raw-Android
  device-pending, two dormant session-persistence diagnostics, three invalid
  nullable-flow operator candidates excluded. All 26 reachable retained
  occurrences and three live engine readers killed; remaining seven occurrences
  are two Android sites and five dead legacy-sheet sites. Every final test has
  a matching-file-hash assertion-failing witness on detached original lib/;
  original/restored controls PASS. Coverage and mutation tables are in the deps
  report; patches, complete JSON logs and source adjudications are archived.
- **Commands/results.** Serial nice19 Flutter controls/mutations with no-pub
  and DEBRIFY_VP_TEST_HOOKS=true; final test `dart analyze`, format, size and
  architecture PASS. Fresh full suite via `suite_evidence.py` vs M1 by identity
  PASS: 13,463 successes, unchanged 13 failures/28 load errors/20 skips; exactly
  70 passing additions, zero changed/missing/new skips, stable tested tree and
  same SDK. Step T's 38 mechanical checks/analyzer inventories remain valid;
  app/tool inputs unchanged. Every parser invocation uses isolated copied
  packages with kernels removed; evidence routing is recorded.
- **Deviations/limits.** Two preliminary focused commands inherited the P8
  runtime fallback; identified fixture data moved into P9, those runs excluded.
  New-case expectations/waits were corrected to original deterministic results,
  preserving assertions. Two throwing-return variants timed out and are not
  credited; finite unwanted-pill exit mutations supplied actual assertion kills.
  No flaky test stabilization needed. Native DSP/audio/rendering, raw mobile/web
  capability checks and compressed passthrough stop/rearm remain device-pending.
  CI stays on applied P8 until the Step-1 production creation commit, which
  registers the six new test files. M2 remains after phases 9–11. STOP here.

### 2026-10-14 — Phase 9 Step 0b (independent sample closure)

- Follows original checkpoint `122896451`; commit receipt in
  `p9/step0b/commit.json`. Claude sample: 16/20 killed (80%). Added two behaviour
  cases and mutation-proved m4/m14 on detached original lib/. Cumulative real
  verification can exceed the per-pass aligner bound; native/session/overlay
  clamp pinned. A late negative session write reaches the suspended settings
  load despite startup reset; native -1.500 and later reset/rearm pinned.
- m7/m8 equivalent under the audited notice generation/timer invariants;
  all 72 cases replay successfully for both. Final sample 18/18 valid killed.
  Deps table records every sample row, source audit, commands, assertions and
  file-hash witnesses. Fixture development attempts excluded and explained.
- Nice19 serial controls/mutations with no-pub and harness define; new-file
  analysis/format PASS. Fresh full suite by identity versus Step 0 PASS:
  13,465 success, unchanged 13 failures/28 load errors/20 skips, exactly two
  passing additions. Evidence `p9/step0b/baseline*`; no allowlisting.
- Application, pubspec, shared H fixture and applied P8 CI unchanged. Step 1
  and the clean-tree gate follow this separately committed addendum.

### 2026-10-14 — Phase 9 Step 1 (production creation checkpoint)

- Follows addendum `2b64e2f19`; final revision in `p9/step1/commit.json`. Applied
  the frozen 21 moves to the 305-line `VpSubtitleAutoSync`/Host bridge. Exhaustive
  807-span classification; 33 retained substitutions, constructor after PiP,
  exact live Host and State-owned fields/teardowns. Earlier 18 destinations and
  PiP adapter unchanged. Facade ratchet 16,829 →16,603 via size update.
- CI current/self-test and both analyzer inputs now P9; P1–P8 histories and
  S/S2/S2b remain. Six test files registered with the harness flag; theme and all
  three source-guard lists extended. Validating reader already chains P9; no
  moved source-text anchor needs retargeting. Three frozen probe import warnings
  recorded; no suppression, import cleanup or older mapping change.
- Nice19 serial focused suite: 82/82 PASS. Current/history/seams and structural
  checks: 14/14 PASS. Scoped CI analyzer/allowlist PASS; comparator 104 identities/
  occurrences, zero additions. Format/idempotence PASS; exact Step-T formatted
  bytes and three optional-comma sites reused with no diagnostic change.
- Evidence `p9/step1/`; no pubspec or behaviour change. Clean-tree full gate
  (all manifest self-tests and both release builds included) follows separately.

### 2026-10-14 — Phase 9 gate (complete; STOP)

- Tested clean Step-1 revision `a2be68e2d`; gate receipt in
  `p9/gate/commit.json`. Fresh full suite versus the Step-0b baseline by identity
  PASS: 13,465 success, identical 13 failures/28 load errors/20 skips, zero
  changed/added/missing/fixed/newly skipped identities. Stable tree, same SDK
  and flags. No flake stabilization or failure allowlisting.
- 42/42 mechanical checks PASS: every other Dart manifest self-test, P9
  universal/all-retained self-comparison and current check, P1–P8 named histories,
  complete Kotlin self-test, S/S2/S2b proofs, size/architecture and negatives.
  Every parser call uses an isolated copied package; kernel deletion/routing
  audited. Facade 16,603, combined bridge 305 lines; size ratchet enforced.
- CI analysis/allowlist and P9 comparator PASS (104 scoped occurrences, zero
  additions); full CI formatting plus changed theme guard PASS. Both release
  builds, apk and macOS, PASS without install/run. Application hashes and
  pubspec remain unchanged throughout the gate. Evidence `p9/gate/`.
- Native DSP/decoded alignment, raw mobile/web predicates and Android
  compressed-passthrough transitions remain device-pending; dormant paths
  unchanged. M2 is after phase 11. No push/merge/switch or production bug fix.
  STOP after the gate commit for independent review.

2026-10-14 — **Phase 9 independent review (Codex `vp-rev9`): no P1/P2 — "No P1s".**
m7/m8 equivalences confirmed (restarts invalidate held alignments; the first
verification is 90 s after a verdict, beyond the 2.4 s hold); m4/m14
closures valid. P3: passthrough mutation notes p018/p021 corrected to the
passthrough-off Android case (still device-pending). Claude sample 16/20 →
18/18 valid after closures. Merged.

### 2026-10-14 — Phase 10 S2c seam extension checkpoint (STOP)

- **Input/scope.** Approved design `e1e73b811`, application base `5c7b704bd`;
  final revision receipt in `p10/s2c/commit.json`. Application delta is exactly
  one `Platform.isAndroid` → `VpS2Hooks.isAndroid` read in the subtitle renderer
  rejection guard. Original current-check/short-circuit order, all other app
  bytes, hook/installer and pubspec preserved. No production move or bug fix.
- **Ledger/CI.** Checkpoint classifies 789 spans: 788 retained, one patched,
  no scaffolding/destinations. Exact patch and earlier destination protection;
  accepted S2/S2b ledger unchanged. CI current/self-test and analyzer manifest
  select S2c with the unchanged P9 inventory; P9 historical check added.
- **Proof/checks.** Nice19 S and S2/S2b/S2c self-proofs, current checkpoint,
  CI universal self-test and P9/S2b same-revision history PASS. All 23 prior
  independent negatives preserved plus eight S2c negatives. Extracted hook/guard:
  five mode controls
  (debug flag/no flag, assertions off, profile, compiled release) PASS; eight
  independent site mutations assertion-killed. Serialized S/S2 guard suites,
  hooks true and false: 7/7 PASS each, complete logs and stable input trees.
  Analyzer retains all 104 identities/occurrences; zero formatting additions or
  comma edits. Guard analysis, format/idempotence, size, architecture and diff
  PASS. Isolated copied parser packages with kernels removed; commands/results
  and exact application delta archived under `p10/s2c/`.
- **Notes/stop.** Preliminary checks exposed a reporting-only assumption in
  S's scaffold summary and a negative matching both current-check guards.
  Summary now uses S's accepted ledger; the negative is scoped to the renderer
  guard. Assertions preserved; rejected attempts archived uncredited, complete
  final runs pass. No T, Step 0, full-suite gate, app build, push/merge/switch
  or device action.
  STOP for S2c independent review; native bitmap rendering remains device-pending.

2026-10-14 — **Phase 10 independent S2c review (`vp-rev10s2c`): no P1/P2/P3.**
Checkpoint `a2e034cb3` accepted. S2c is the ORIGINAL for Phase-10 behavior and
mutation proofs; `5c7b704bd` remains the phase-9 historical merge checkpoint.

### 2026-10-14 — Phase 10 prerequisites; frozen Host correction pending

- S2c original re-measured: five methods, 150 AST statement/branch/literal sites,
  exactly 23 retained executable references. All 36 independent nice19 checks
  PASS: 26 existing Dart manifest self-tests, P1–P9 at their named merges and
  Kotlin self-test. Every Dart invocation uses an isolated copied parser with
  copied kernels removed. Evidence `p10/stepT/independent-results.json`.
- Complete S2c original suite by identity versus P9 gate PASS: 13,465 successes,
  unchanged 13 failures/28 load errors/20 skips, zero added/missing/changed/fixed
  identities. SDK identical; tested tree stable. `p10/step0/original-suite*`.
- **Blocking design mismatch:** the explicitly frozen 17-name /20-declaration
  Host and three chains omit `isAndroid`, now required by the accepted S2c
  predicate inside the moved diagnostics method. Preserving it without a facade
  back-import needs `bool get isAndroid => VpS2Hooks.isAndroid;` and the fourth
  exact chain. Proposed correction is 18 names /21 declarations /four chains;
  `p10/stepT/host-correction-proposal.json`. Direction requested; not applied.
- Step T materialization/probe/commit and full Step 0 remain incomplete.
  Eighteen caller-case development controls and two pilot assertion witnesses
  are preserved only in the detached original/evidence; they are not credited
  as a completed coverage matrix or final mutation sweep. Main application,
  pubspec and CI unchanged; no production move, push/merge/switch or device work.

### 2026-10-14 — Phase 10 plan-owner Host correction approved

Claude approved the proposal recorded in
`p10/stepT/host-correction-proposal.json`: 18 Host names /21 declarations,
four registered chains, and live `isAndroid` forwarded to `VpS2Hooks.isAndroid`
at the original read. Frozen ownership and the resolution now match S2c;
no destination facade import, production change or CI transition. Plan-only
checkpoint; Step T and full Step 0 continue against `a2e034cb3` application code.
Validation: exact diff and `git diff --check`.

### 2026-10-14 — Phase 10 Step T complete (application still S2c)

- Revision: original `a2e034cb3`, plan-owner correction `2adc21ec2`; this tooling
  checkpoint is archived in `p10/stepT/commit.json`. Complete draft materializes
  five moves, 782 retained and two patched spans (789 exhaustive); 23 retained
  occurrences, exact 18-name /21-declaration Host and four registered chains.
  Hypothetical destination 223 lines; State fields and teardown stay in place.
- Commands/results: `draft_vplayer_subtitle_apply_moves.py`, real-config fixture
  and universal `check_dart_moves --self-test --self-compare-original`, all-retained
  self-compare, S and S2/S2b/S2c proofs PASS. P1–P9 named `--at`, 26 existing
  Dart manifest self-tests and Kotlin self-test PASS in the unchanged prerequisite
  evidence. All 19 earlier destinations protected; isolated copied parsers,
  copied kernels removed, nice19 throughout.
- Root/probe analyzer 104 scoped identities, strict original 176; inventory
  preserves every earlier mapping. Optional-comma proof: one destination comma,
  zero facade comma edits, idempotence, zero formatting diagnostic additions.
  Evidence: `p10/stepT/` commands, complete logs and identity reports.
- Deviation: first universal command completed its assertion phase but rejected
  the draft in its CLI postamble without `--self-compare-original`. That attempt
  is archived uncredited; the full corrected command completed with exit 0.
  Final generator replay produces the identical manifest. No application,
  pubspec or production CI transition; Step 0 continues on S2c.

### 2026-10-14 — Phase 10 Step 0 complete; STOP before production moves

- Revision: original S2c application `a2e034cb3`, tooling `1a51002e7`; final
  characterization commit recorded in `p10/step0/commit.json`. Added 87 original
  caller cases in nine behavior files plus one shared H driver. Unchanged files
  pass on detached S2c and current worktree; no private State/attempt injection.
- Coverage: all five moves, 152 systematic AST points and 23 retained references.
  Final mutations: 110 assertion kills, seven source-audited original-caller
  equivalences, 35 flow/type-invalid candidates (no credit); 20/20 live retained
  references killed, three dormant legacy sheet references frozen. Every new
  test has a final-file original assertion witness. Full matrix, exact patches,
  physical A/B storage writes, commands/hashes and classifications in deps and
  `p10/step0/`.
- Final serial original/current focused runs PASS (87 cases each); new-test
  analyzer zero issues; format/idempotence, size/architecture and diff PASS.
  Fresh `suite_evidence.py run/compare` versus the S2c original suite PASS:
  13,552 successes, unchanged 13 failures/28 load errors/20 skips; exactly 87
  additions, zero missing/changed/fixed/newly skipped identities. Tested tree
  stable, same SDK/flags. `after-step0*`, baseline comparison and checks archived.
- Notes: source-specific rejection and separate request counts prevent later
  defaults from masking retained-call gaps. A non-pumping mutation matcher and
  preliminary fixture expectations were corrected on the original; failed
  attempts remain uncredited. One owned orphan tester from an uncredited timeout
  was cleaned up. Seven equivalences are documented, not removed. Cross-profile
  writes, stale rollback/native effects and disposed notifier behavior remain
  as-is in Follow-ups. No allowlist/pubspec/production change; CI/source/theme
  transition and the actual move remain Step 1. No build or device work.

### 2026-10-14 — Phase 10 Step 0b independent sample closure

- Revision: ORIGINAL `0055d29a7` (S2c lib tree); addendum revision recorded in
  `p10/step0b/commit.json`. Claude's independent sample: 18/20 assertion kills
  (90%); n10/n15 source-audited equivalent, 18/18 non-equivalent killed.
- Proof: all pointer/generation producers either increment before clearing or
  mark handled before clearing; persisted is stamped only after successReturned
  and that flag is never reset. No reachable proposed window distinguishes the
  mutants. Exact detached original control and both replays complete with all
  87 existing cases passing; hashes/patches/commands in `p10/step0b/`.
- Deps matrix/table updated. No application, test, dependency or allowlist change;
  reuse completed Step-0 baseline (13,552 successes, unchanged 13 failures/28
  load errors/20 skips; 87 original additions only). Guards retained verbatim.
  Production move and gate follow in separate commits.

### 2026-10-14 — Phase 10 Step 1 applied

- Revision: addendum `8fb405474`; production revision recorded in
  `p10/step1/commit.json`. Five moves into the 223-line subtitle apply bridge;
  facade 16,477 lines (ratchet lowered from 16,603). Exact 18-name /21-declaration
  Host, four chains, two patched declarations and 23 references; State-owned
  diagnostics/notifier and teardown order preserved.
- Current manifest PASS, zero differences; all 87 focused original-caller cases
  PASS on moved code. Format, size/architecture, scoped analyzer comparator and
  retargeted S2/S2b/S2c source proof PASS. Evidence `p10/step1/`; full gate follows
  on this clean commit. S2c proof validates the live reader result and retains
  earlier independent negatives, adding five exact adapter-projection negatives.
- CI current/self-test and both analyzer inputs now P10; P1–P9 histories, all
  seam proofs, nine behavior registrations, theme/source lists updated. No
  pubspec or behavior change. Initial projection expected-shape error (missing
  annotation tokens) is archived uncredited; corrected proof rerun passes.

### 2026-10-14 — Phase 10 gate complete; STOP

- Tested clean Step-1 `8032eda34`; gate revision recorded in
  `p10/gate/commit.json`. Fresh full suite versus the Step-0b baseline by identity
  PASS: 13,552 success, identical 13 failures/28 load errors/20 skips; zero
  changed/added/missing/fixed/newly skipped identities. Stable tree and same SDK
  and harness flag. No flake stabilization or allowlisting.
- All 43 mechanical jobs PASS: every other Dart manifest self-test, P10
  universal/current, P1–P9 named histories, Kotlin checker self-test, S/S2/S2b/
  S2c proofs, size/architecture and negatives. Isolated copied parser packages
  and kernel deletion/routing audited. Facade 16,477; bridge 223 lines.
- CI-scope analyzer/allowlist and P10 comparator PASS (104 scoped occurrences,
  zero additions); CI formatting and changed theme guard PASS. Both apk and
  macOS release builds PASS, serialized after the suite, without install/run.
  Application/input hashes and pubspec unchanged throughout. Evidence
  `p10/gate/`; exact commands, complete logs, metadata and artifact receipts.
- Physical native decoder/bitmap rendering and PiP presentation remain
  device-pending. Dormant paths and characterized original defects preserved;
  M2 follows phase 11. No production bug fix or push/merge/switch. STOP for review.

### 2026-10-14 — Phase 11 prerequisites; numeric ledger clarification pending

- Revision: original `7fdf59370`, approved design `3720cfe96`; receipt in
  `p11/prerequisites-commit.json`. Application/pubspec/CI unchanged.
- Actual frozen table has 15 declarations (13 methods/getters +two fields),
  not 14. Retained ledger has 28 occurrences (22 redirects +six unchanged reset
  callers), not 27: reset's cleanup at 15077 is omitted. Only three chains occur
  in named moves; sync-reset stays retained. Owner direction requested before
  freezing counts; no membership silently added/dropped or source call invented.
- Evidence-only complete prototype: 15 moves/770 retained/two patched, zero
  comparison differences; formatted three destinations 303/282/412, all ≤500.
  Minimal live Hosts/action signatures and scaffolds reviewable in
  `p11/stepT/host-and-size-proposal.json`. Selected-audio remains State-owned;
  the two owned initializers are inert. Optional-comma sites/idempotence archived.
- All 40 existing prerequisite checks PASS: 26 other Dart manifests, P1–P10
  named histories, Kotlin597, existing universal checker and all seam proofs.
  Isolated copied parsers/kernels, nice19; original suite stable and identical to
  P10 gate (13,552 successes, same 13 failures/28 load errors/20 skips).
  Analyzer root104/strict177/prototype114, no errors; prior identities preserved.
- 20 pilot caller cases only in detached original pass; each mutation-proven
  with final files, including real bytes and files before fixture deletion.
  Final analysis/format clean; original lib restored. Initial unscoped pilot and
  missing prototype import are uncredited; reruns pass. Full discovery/priority,
  restore/language, series-write matrix, systematic sweep and additions-only
  Step-0 baseline remain. No P11 manifest frozen, production move or CI transition.
  Detailed ledgers/commands/results in deps and `p11/`; STOP pending direction.

### 2026-10-14 — Phase 11 plan-owner numeric correction approved

- Base `7fdf59370`; approved proposal
  `p11/stepT/host-and-size-proposal.json`. Plan counts now match the measured
  named table: 15 moves, 28 references, three used chains. Reset remains retained
  and selected audio State-owned. Hosts frozen exactly as proposed; destinations
  format to 303/282/412 lines. No production changes.
- Documentation consistency and `git diff --check` pass. Step T and the full
  Step-0 characterization continue under the approved correction.


### 2026-10-14 — Phase 11 Step T complete (application still original)

- Base `7fdf59370`; plan correction `07b61398b`; commit receipt
  `p11/stepT/commit.json`. Complete draft `vplayer_p11.json`: 787 classified
  declarations, 15 moved/770 retained/two patched, 28 references, three used
  chains. Destinations format to 303/282/412; approved Hosts frozen exactly,
  selected audio State-owned. All 20 earlier destinations protected.
- `draft_vplayer_subtitle_sources_moves.py --parser-package <isolated>
  --probe <p11/stepT/frozen>` and the real-config negatives PASS. Full
  `check_dart_moves.py --manifest .../vplayer_p11.json --self-test
  --self-compare-original --parser-package <isolated>` PASS: 787 all-retained
  spans, zero differences. P1–P10 named `--at`, 26 other Dart self-tests,
  Kotlin597 and S/S2/S2b/S2c proofs PASS; valid unchanged prerequisites reused.
- Analyzer root104/strict177/materialized114, zero errors and no added
  async-context identities. Earlier mappings preserved in the P11 inventory.
  Optional-comma sites/idempotence archived. Completed commands/results in
  `p11/stepT/frozen-result.json`. Independent disjoint edit-list ordering differs
  from the prototype; canonical declarations, Hosts, scaffolds and bodies agree.
  Application/pubspec/CI unchanged. Step 0 continues; no production moves.

### 2026-10-14 — Phase 11 Step 0 complete (STOP before production moves)

- **Revision/original.** Follows Step T `2ee13b490` and approved numeric correction
  `07b61398b`; application original **`7fdf59370`**. Step-0 commit receipt:
  `refactor-evidence/vplayer/p11/step0/commit.json`. App/pubspec unchanged;
  all three destinations remain evidence-only; no production/CI transition.
- **Characterization.** **190 passing original-caller cases** across 15 scenario
  files: streamed raw/gzip/ZIP bytes and independent exact 15 s budgets; cache
  formats/bounds/client closure; actual cleanup files and held write/rename
  leaks; discovery/priority/manual/audio/profile/disposal races and retries;
  restore/default-language captures; physical series writes in both profiles;
  aliases/title metadata/pt-BR; early inputs; every live retained caller. Public
  selections use step-H `finish()`; no private State or source-text coverage.
  The shared driver adds only an opt-in legacy-profile fixture flag (true default).
- **Sweep/proofs.** All 15 declarations and 28 references re-measured. AST 611:
  **400 assertion kills /18 evidenced equivalence sites /two dormant catches /
  191 invalid first candidates**; **67 typed alternatives all assertion-killed**.
  All 25 live references assertion-killed; three unified-menu legacy references
  dormant. Every final case-file hash has an original assertion-failing witness.
  Full matrix/mutation/per-test tables in the deps report; exact patches,
  completed logs, IDs, input hashes and reasons under `p11/step0/`.
- **Baseline/checks.** Nice19, serialized suites:
  `suite_evidence.py run vplayer/p11/step0/final-suite --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true`, then `compare --against
  original-suite.jsonl final-suite.jsonl` and strict identities PASS:
  **13,742 success /13 failure /28 load error /20 skip**, exactly 190 additions,
  zero old changes/missing/newly skipped/fixed identities; same SDK/flags and
  stable tested tree. Test analysis/format, size and architecture PASS.
  Unchanged Step-T P1–P10 histories, seam proofs and all Dart/Kotlin self-tests
  retained; nested parser invocations isolated under `.dart_tool/vplayer_parser/`.
- **Deviations/limits.** Failed filters/fixture assumptions, type-invalid/error-only
  mutations and the deliberately interrupted concurrency 1 suite are uncredited;
  final controls/replays use the correct original behavior and baseline flags.
  Original late restores, late file registration, leaked 6 s initialization timer
  and cross-profile series map writes are pinned and recorded in Follow-ups.
  Retired-State cache publication is unobservable; native decoding/real metadata
  and durability stay device-pending. No bug fix, real transport, build/run/install,
  device action, push/merge/branch switch. STOP for independent Step-0 sampling;
  production moves, registrations and ratchet lowering remain Step 1.

### 2026-10-14 — Phase 11 Step 0b independent sample closure

- Original `d5fd82210` (lib `7fdf59370`); addendum revision receipt
  `p11/step0b/commit.json`. Claude sample 16/20 (80%); q3/q12/q13/q16 now
  assertion-killed on the detached original: final 20/20 (100%). Five new
  caller cases pin forced-only/audio policy, addon id collisions, mid-cleanup
  manual/audio cancellation and pre-success audio persistence during late restore.
- q16 is real: a public audio write before late restore success does not mark
  its attempt persisted; a later decoder rollback changes native selection
  without undoing that physical write. Existing behavior retained; no source
  tests or private State injection. Root and detached controls pass with the
  final test hash; exact patches/completed witnesses in `step0b/` and deps table.
- `suite_evidence.py run vplayer/p11/step0b/baseline --no-pub
  --dart-define=DEBRIFY_VP_TEST_HOOKS=true`, `compare --against
  step0/final-suite.jsonl baseline.jsonl` and strict identity comparison PASS:
  13,747 successes, same 13 failures/28 load errors/20 skips; exactly five
  passing additions, no old changes; stable tree and same SDK/flags. Test
  analysis/format PASS. 195 P11 cases total; original sweep remains intact.
- Failed pilot fixture/compile assumptions and initial wrong-CWD control are
  archived uncredited; final serial controls/replays complete and lib restored.
  No app/pubspec/allowlist/CI change or bug fix. Production Step 1 follows.

### 2026-10-14 — Phase 11 Step 1 applied

- Follows addendum `10d4a06f3`; revision receipt `p11/step1/commit.json`.
  Exact 15 moves/28 references into 303/282/412-line siblings; facade
  15,880 (ratchet lowered from 16,477). Three eager inert assignments after
  subtitleApply, two addon fields, frozen live Hosts, three chains and one
  apply-adapter projection; State fields/reset/dispose positions preserved.
- `check_dart_moves.py --manifest .../vplayer_p11.json --parser-package
  <isolated>` PASS zero differences and exact Step-T materialization.
  195 focused original-caller cases plus theme guard PASS on moved code;
  comparator114 scoped diagnostics/zero additions, CI analyzer/allowlist,
  format, size/architecture and scoped HTTP import negatives PASS.
- CI current/self-test and both analyzer inputs P11, historical P1–P10 and
  seams retained; behavior/theme/source-guard registrations complete. Seven
  frozen unused imports registered exactly from the approved Step-T probe
  under rule6; first missing-registration check archived uncredited. Exact
  addon HTTP pair registered with positive/neighbor/shared-preferences negatives;
  exit is the existing service/data ownership follow-up. No broad exemption.
- No application bug fix, pubspec or assertion change. Clean-tree gate follows;
  physical metadata/native decoding, TV interaction and cleanup durability stay
  on the device checklist. No device/run/install/push/merge/switch action.

### 2026-10-14 — Phase 11 gate complete; STOP

- Tested clean Step-1 `fba8f3de1`; gate revision recorded in
  `p11/gate/commit.json`. Fresh full suite versus the Step-0b baseline by identity
  PASS: 13,747 success, identical 13 failures/28 load errors/20 skips; zero
  changed/added/missing/fixed/newly skipped identities. Stable tree and same SDK
  and harness flag. No test flake stabilization or failure allowlisting.
- All 44 mechanical jobs PASS: every other Dart manifest self-test, P11
  universal/current, P1–P10 named histories, Kotlin checker self-test, S/S2/S2b/
  S2c proofs, size/architecture and negatives. Isolated copied parser packages
  and kernel deletion/routing audited. Facade 15,880; bridges 303/282/412 lines.
- CI-scope analyzer/allowlist and P11 comparator PASS (114 scoped occurrences,
  zero additions); CI formatting and changed theme guard PASS. Both apk and
  macOS release builds PASS, serialized after the suite, without install/run.
  Application/input hashes and pubspec unchanged throughout. Evidence
  `p11/gate/`; exact commands, complete logs, metadata and artifact receipts.
- Physical native decoding/bitmap/forced metadata, PiP, TV remote selection
  and preference/temp-file durability across restarts remain device-pending. Dormant paths and characterized
  original defects preserved; M2 follows phase 11. No production bug fix or push/merge/switch. STOP for review.

2026-10-14 — **Phase 11 independent review (Codex `vp-rev11`): no P1/P2 — "No P1s".**
15/28/3 ledger, bridges 303/282/412, 195 + 87 + 10 cases and gate identities
verified; q16 is non-equivalent with a physical-write witness. P3: `//` →
`||` (logical OR) in the p485/p496/p504/p524 equivalence rows, corrected.
Claude sample 16/20 → 20/20 after closures. Merged; M2 follows.

### 2026-10-14 — Integration milestone M2 gate complete; STOP

- Merged base `0c2fb62e8`, branch `refactor/vplayer-m2`; gate revision and tested
  input/tree metadata in `m2/gate/commit.json`. One registered cross-phase
  scenario, shared step-H harness, real UTF-8 SRT/parser/compute alignment and
  deterministic metadata transport. Automatic +2114 ms, manual +900 ms during
  held alignment, decoder rollback to previous path, file/path/timing reset,
  automatic audio-policy reselection after manual flags reset, same-State
  renderer fallback with fresh-engine subtitle reselection, profile handoff,
  per-profile physical track/style writes and held PiP visibility restoration.
- Unchanged final file passes on S2c original `a2e034cb3`, lib tree
  `e2543c0219d9cc047bdc950723b78030cf092ed6`, and merged code. S2c already
  includes the P9 extraction: M2 parity covers P10–11; P9 keeps its earlier
  characterization and has M2 mutation witnesses on both trees. Six original
  assertion kills across P9/10/11 plus one independent merged P9 bridge kill;
  unmodified controls before/after pass. `m2/scenario/parity.json` and
  `m2/mutations/` archive exact bytes/patches, completed runs and assertions.
- Full suite by identity vs P11 gate PASS: exactly one passing M2 addition,
  13,748 success with identical 13 failures/28 load errors/20 skips; no changed/
  missing/newly skipped identities, same SDK/flags, stable staged test tree.
  All 44 mechanical jobs PASS (Dart self-tests, P11 current, P1–P10 histories,
  Kotlin, all seam proofs, size/architecture/negatives), isolated parser/kernel
  deletion audit; CI analyze/allowlist/P11 comparator PASS (114 scoped
  occurrences, zero additions), format PASS. Both serialized apk/macOS release
  builds PASS, no install/run. `m2/gate/` contains completed evidence/receipts.
- Evidence only under `refactor-evidence/vplayer/m2/`; exact command/result
  records, hashes and fixture note. The pending-PiP observation was reproduced
  on S2c before correcting fixture ordering; no flaky-test stabilization, shared
  fixture edit, weakened assertion, failure allowlisting or production change.
  App/native code, dependencies and pubspec unchanged. Native decoding and
  physical PiP presentation remain device-pending. No later phase or
  push/merge/branch switch. STOP for review.

### 2026-10-14 — Phase 12 Step T complete (application still original)

- Design `2356e5404`; named original/base `6053efabd`. Complete draft:
  781 declarations (772 retained/eight moved/one patched State constructor),
  seven retained substitutions, 23 earlier destinations; exact inert Hosts,
  live widget selectors/P11 chain, facade UI routing and lexical contexts/setters.
  Normal-format evidence-only destinations **263/470** lines, both ≤500.
- Materialization and universal real-config self-test/all-retained comparison
  PASS zero differences. Independent declared-corruption lexical negatives
  reject both setters and each builder context. Optional-comma anchor proof,
  formatting idempotence and final comparison archived.
- Fresh P1–P11 `--at` (P11 `0c2fb62e8`) and all S/S2/S2b/S2c proofs PASS.
  Other 26 Dart manifest self-tests and Kotlin's 597 assertions reuse completed
  M2 gate results after exact tooling/core/parser/manifest/app/SDK input checks;
  all runs used isolated parser packages with kernels removed. The changed
  universal registration and P12 negatives were rerun completely.
- Analyzer root114/strict188/unformatted123/formatted124, zero errors. The
  identification declaration gains three receiver-induced async-context infos
  and one formatting-induced braces info; six facade imports become unused.
  Recorded identities/maxima preserve earlier mappings, with no lint fix.
  Evidence `p12/stepT/` includes commands, complete receipts, memberships,
  Hosts and input hashes; initial failed pilots are uncredited.
- Application/pubspec/CI/size baseline unchanged. Step 0 continues at original
  application code; no production extraction or later step is started.

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

## Phase 5 design review resolution (Codex `vp-design`, 2026-10-12) — "No P1s"

Split into phase 5 (Trakt) and phase 6 (Simkl + MDBList). P2s folded:
exact Hosts incl. borrowed seek guards (`_resumeWriteGuard`,
`_stremioTvStartupSeek`, `_episodeTrackerProgressImdbId` State-owned) and
the Simkl→`traktProgress` routing; skip adapter as a P5 `patched` facade
declaration (not `earlier_patches`); isolate-wide delegating HTTP
transport + credential seeding + cipher barrier; tracker-specific
protocols and error propagation; async reader/initialization races;
source-text guard retarget via the validating reader. P3s: staged phases,
concrete CI/comment ownership.

## Phase 6 design review resolution (Codex `vp-design`, 2026-10-12) — "No P1s"

(Two "model at capacity" interruptions; resumed in the same session.) P2s
folded: disabled-at-start vs disabled-mid-session characterized as-is;
pending MDBList checkpoints across switch/dispose/profile change and held
Simkl responses incl. the 409 recovery; startup ordering and heartbeat
contracts. P3s: full `_trakt.traktProgress` → `_host.traktProgress` chain
registration with frozen adapter body; accurate source-guard prefix update.
Membership confirmed: 24 moves, 59 retained references; Hosts 19/15.

## Phase 7 design review resolution (Codex `vp-design`, 2026-10-12) — "No P1s"

P2s folded: concrete cross-profile write characterization (pre-existing
corruption risk recorded in Follow-ups, preserved); one-shot scoped to
position dispatch with EOF/overlap/tracker cases and EOF order; early
threshold in both directions with a selective loader barrier; caught vs
uncaught failure state and partial cleanup failure. P3s: corrected
11-occurrence ledger (no playlist-index caller of the episode mark);
explicit CI/theme/analyzer transition.

## Phase 8 design review resolution (Codex `vp-design`, 2026-10-13) — "No P1s"

Chose option (b): seam S2 (platform predicates, separate from S) so
mobile background pause/resume and PiP wiring are characterized; native
presentation device-pending. P2s folded: retained `onPause` closure
(recording teardown) and no background resume save; Step H separates
"entered held boundary" from "completed" and proves races stay concurrent;
explicit async boundary matrix; wakelock queued-write semantics. P3s:
ownership (`_isPipActive`, `_pausedByLifecycle`, `_lifecycle` State-owned;
`_backgroundedAt` moves), exact Host signatures, 7 `pipOwner`
substitutions, 22-occurrence ledger, concrete M1 and CI.

## Phase 9 design review resolution (Codex `vp-design`, 2026-10-14) — "No P1s"

P2s folded: one combined bridge file (owned-field guard); session-only
offset and settings/profile race cases; real engine activation with fixture
subtitles and metadata; both teardown protocols frozen in place plus
startup windows. P3s: revised ownership map (settings, external path,
overlay flag, pill notifier and fade cache State-owned; selection-correction
notifier State-owned), exact Host, 33-occurrence ledger, CI, executable M2.

## Phase 10 design review resolution (Codex `vp-design`, 2026-10-14) — "No P1s"

P2s folded: both diagnostic fields State-owned, five moves, frozen 18-name
Host and chain substitutions, PiP adapter patch registration; S2c chosen
for the Android renderer rejection guard (separately reviewed); notifier
listener classified dormant, corrections characterized via the unified
menu; three distinct late-failure behaviours pinned as-is; persistence race
matrix with physical writes in both profiles. P3s: 23-reference ledger;
explicit CI transition.

Plan-owner correction (Claude, 2026-10-14): the accepted S2c Android
predicate requires the live `bool get isAndroid` Host projection with adapter
body `VpS2Hooks.isAndroid`, read at the original moment. The corrected frozen
Host has 18 names /21 declarations and four complete registered chains. This
preserves S2c without a destination-to-facade import; proposal and exact patch:
`refactor-evidence/vplayer/p10/stepT/host-correction-proposal.json`.

## Phase 11 design review resolution (Codex `vp-design`, 2026-10-14) — "No P1s"

P2s folded: three collaborators to respect the 500-line cap
(`_resetSubtitleState` retained); fields and Hosts frozen (only the temp-file
set and priority queue move); streaming HTTP fixture and cleanup races;
discovery/priority concurrency matrix incl. retries outliving the route;
restore/default-language races and the series physical-write branch. P3s:
28-reference ledger (corrected by the approved Step-T measurement), single patched adapter, corrected ownership map and
language terminology, concrete M2 inputs and CI transition.


Phase-11 plan-owner resolution (Claude, 2026-10-14): the numeric ledger
correction in `refactor-evidence/vplayer/p11/stepT/host-and-size-proposal.json`
is approved: 15 moves (13 methods/getters +two fields), 28 references and three
used chains. Every named table entry is preserved; `_resetSubtitleState` stays
in place. The proposed three Hosts are frozen, with normal-format sizes
303/282/412. This resolves the prerequisite clarification without changing
application behaviour or authorizing production moves at Step T/0.

## Phase 12 design review resolution (Codex `vp-design`, 2026-10-14) — "No P1s"

P2s folded: manual identity affects subtitle discovery and the prefetch
fallback only (not trackers/skip) — characterized as-is; search has no
debounce, dialog bypassed when coordinates exist, error UI only via
inventory/storage failure; presentation helper frozen (episode dialog
grouped with the sheet, facade Host routing, live State context for tile
taps, lexical setters/contexts guarded); async matrix at the real guards
and commit points. P3s: 8-method/7-reference ledger, no adapter patches,
corrected phase-1 helper names; concrete TV and CI coverage.
